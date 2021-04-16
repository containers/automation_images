

# This file is intended to be sourced by other scripts running on
# aa Fedora or Ubuntu VM during various stages of initial setup.
# Using it in any other way or context unlikely to do anything
# useful for you.

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")

# By default, assume we're not running inside a container
CONTAINER="${CONTAINER:-0}"

OS_RELEASE_VER="$(source /etc/os-release; echo $VERSION_ID | tr -d '.')"
OS_RELEASE_ID="$(source /etc/os-release; echo $ID)"
OS_REL_VER="$OS_RELEASE_ID-$OS_RELEASE_VER"

SRC=$(realpath $(dirname "${BASH_SOURCE[0]}")/../)
CUSTOM_CLOUD_CONFIG_DEFAULTS="$SCRIPT_DIRPATH/cloud-init/$OS_RELEASE_ID/cloud.cfg.d"
# Avoid getting stuck waiting for user input
[[ "$OS_RELEASE_ID" != "ubuntu" ]] || \
    export DEBIAN_FRONTEND="noninteractive"

# This location is checked by automation in other repos, please do not change.
PACKAGE_DOWNLOAD_DIR=/var/cache/download

INSTALL_AUTOMATION_VERSION="2.1.4"

PUSH_LATEST="${PUSH_LATEST:-0}"

SUDO=""
if [[ "$UID" -ne 0 ]]; then
    SUDO="sudo"
fi

if [[ "$OS_RELEASE_ID" == "ubuntu" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    SUDO="$SUDO env DEBIAN_FRONTEND=$DEBIAN_FRONTEND"
fi

if [[ -d "/usr/share/automation" ]]; then
    source /etc/automation_environment
    #shellcheck disable=SC1090,SC2154
    source $AUTOMATION_LIB_PATH/common_lib.sh

    # Shortcuts to common retry/timeout calls
    lilto() { err_retry 8 1000 "" "$@"; }  # just over 4 minutes max
    bigto() { err_retry 7 5670 "" "$@"; }  # 12 minutes max
else  # Automation common library not installed yet
    echo "Warning: Automation library not found. Assuming it's not yet installed" \
        > /dev/stderr
    die() { echo "ERROR: ${1:-No error message provided}"; exit 1; }
    lilto() { die "Automation library not installed; Required for lilto()"; }
    bigto() { die "Automation library not installed; Required for bigto()"; }
fi

install_automation_tooling() {
    # This script supports installing all current and previous versions
    local installer_url="https://raw.githubusercontent.com/containers/automation/master/bin/install_automation.sh"
    curl --silent --show-error --location \
         --url "$installer_url" | \
         $SUDO env INSTALL_PREFIX=/usr/share /bin/bash -s - \
        "$INSTALL_AUTOMATION_VERSION" "$@"
    # This defines AUTOMATION_LIB_PATH
    source /usr/share/automation/environment
    #shellcheck disable=SC1090
    source $AUTOMATION_LIB_PATH/common_lib.sh
}

custom_cloud_init() {
    if [[ -d "$CUSTOM_CLOUD_CONFIG_DEFAULTS" ]]
    then
        echo "Installing custom cloud-init defaults"
        $SUDO cp -v "$CUSTOM_CLOUD_CONFIG_DEFAULTS"/* /etc/cloud/cloud.cfg.d/
    else
        echo "Could not find any files in $CUSTOM_CLOUD_CONFIG_DEFAULTS"
    fi
}

# This function may only/ever be used within Cirrus-CI
set_gac_filepath(){
    # shellcheck disable=SC2154
    if [[ -z "$CI" ]] || [[ "$CI" != "true" ]] || [[ "$CIRRUS_CI" != "$CI" ]]; then
        die "Unexpected \$CI=$CI and/or \$CIRRUS_CI=$CIRRUS_CI"
    elif ((${#GAC_JSON}<=0)); then
        die "Required (secret) \$GAC_JSON value appears to be empty"
    elif grep -iq "ENCRYPTED" <<<"$GAC_JSON"; then
        die "Decrpytion of \$GAC_JSON failed."
    fi
    set +x;
    GAC_FILEPATH=$(mktemp -p '' '.XXXXXXXX.')
    export GAC_FILEPATH
    trap "rm -f $GAC_FILEPATH" EXIT
    echo "$GAC_JSON" > "$GAC_FILEPATH"
    unset GAC_JSON;
}

get_kubernetes_version() {
    local KUBERNETES_VERSION
    case "$OS_REL_VER" in
        fedora-32)
            KUBERNETES_VERSION="1.15" ;;
        fedora-33)
            KUBERNETES_VERSION="1.18" ;;
        fedora-34)
            KUBERNETES_VERSION="1.20" ;;
        *) die "Unknown/Unsupported \$OS_REL_VER '$OS_REL_VER'"
    esac
    echo "$KUBERNETES_VERSION"
}

# Warning: DO NOT USE the following functions willy-nilly!
# They are only intended to be called by other setup scripts, as the very
# last step during the build process.  They're purpose is to "reset" the
# VM so all the first-boot operations happen again normally (like
# generating new ssh host keys, resizing partitions, etc.)

# Ref: https://cloud.google.com/compute/docs/oslogin
# Google "OS-login" service manages persistent accounts automatically.
# The "packer" tool also does this during image creation, and the two
# have been observed causing conflicts upon reboot.  When finalizing
# an image for re-use, remove all standard user accounts AND home
# directories.
clean_automatic_users() {
    DELUSER="deluser --remove-home"
    DELGROUP="delgroup --only-if-empty"
    if [[ "$OS_RELEASE_ID" == "fedora" ]]; then
        DELUSER="userdel --remove";
        DELGROUP="groupdel"
    fi
    # Avoid needing to parse login.defs (fedora) and deluser.conf (Ubuntu)
    # for the UID/GID ranges standard user accounts.
    cd /home || exit
    for account in *; do
        # Cannot remove active user executing sudo - assume this is "packer"
        # and will be removed by the tool upon image build completion.
        if id "$account" &> /dev/null && [[ "$account" != "$USER" ]]; then
            $SUDO $DELUSER "$account"
            $SUDO $DELGROUP "$account" || true
        fi
    done
    $SUDO rm -rf /home/*/.ssh/*
}

common_finalize() {
    set -x  # extra detail is no-longer necessary
    cd /
    clean_automatic_users
    $SUDO cloud-init clean --logs
    $SUDO rm -rf $SCRIPT_DIRPATH
    $SUDO rm -rf /var/lib/cloud/instanc*
    $SUDO rm -rf /root/.ssh/*
    $SUDO rm -rf /etc/ssh/*key*
    $SUDO rm -rf /tmp/*
    $SUDO rm -rf /tmp/.??*
    echo -n "" | $SUDO tee /etc/machine-id
    $SUDO sync
    if ! ((CONTAINER)); then
        $SUDO fstrim -av
    fi
}

# Called during VM Image setup, not intended for general use.
rh_finalize() {
    set +e  # Don't fail at the very end
    set -x
    $SUDO dnf clean all
    $SUDO rm -rf /var/cache/{yum,dnf}
    $SUDO rm -f /etc/udev/rules.d/*-persistent-*.rules
    $SUDO touch /.unconfigured  # force firstboot to run
    common_finalize
}

# Called during VM Image setup, not intended for general use.
ubuntu_finalize() {
    set +e  # Don't fail at the very end
    set -x
    $SUDO apt-get -qq -y autoremove
    $SUDO rm -rf /var/cache/apt
    $SUDO rm -rf /var/lib/apt/lists/*
    common_finalize
}

finalize() {
    if ((CONTAINER)); then
        echo "Skipping running finalize() in a container"
        return 0
    elif [[ "$OS_RELEASE_ID" == "centos" ]]; then
        rh_finalize
    elif [[ "$OS_RELEASE_ID" == "fedora" ]]; then
        rh_finalize
    elif [[ "$OS_RELEASE_ID" == "ubuntu" ]]; then
        ubuntu_finalize
    else
        die "Unknown/Unsupported Distro '$OS_RELEASE_ID'"
    fi
}
