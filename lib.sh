

# This file is intended to be sourced by other scripts running on
# aa Fedora or Ubuntu VM during various stages of initial setup.
# Using it in any other way or context unlikely to do anything
# useful for you.

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")

# By default, assume we're not running inside a container
CONTAINER="${CONTAINER:-0}"

OS_RELEASE_VER="$(source /etc/os-release; echo $VERSION_ID | cut -d '.' -f 1)"
OS_RELEASE_ID="$(source /etc/os-release; echo $ID)"
OS_REL_VER="$OS_RELEASE_ID-$OS_RELEASE_VER"

SRC=$(realpath $(dirname "${BASH_SOURCE[0]}")/../)
CUSTOM_CLOUD_CONFIG_DEFAULTS="$SCRIPT_DIRPATH/cloud-init/$OS_RELEASE_ID/cloud.cfg.d"
# Avoid getting stuck waiting for user input
[[ "$OS_RELEASE_ID" != "ubuntu" ]] || \
    export DEBIAN_FRONTEND="noninteractive"

# This location is checked by automation in other repos, please do not change.
PACKAGE_DOWNLOAD_DIR=/var/cache/download

# TODO: Lock down to specific version number for stability
INSTALL_AUTOMATION_VERSION="latest"

SUDO="env"
if [[ "$UID" -ne 0 ]]; then
    SUDO="sudo"
    [[ "$OS_RELEASE_ID" != "ubuntu" ]] || \
        SUDO="$SUDO env DEBIAN_FRONTEND=noninteractive"
fi

if [[ -d "/usr/share/automation" ]]; then
    # Since we're not a login-shell, this doesn't always automatically load
    # (via other means, pointing at this file)
    source /usr/share/automation/environment
    for libname in defaults anchors console_output utils; do
        #shellcheck disable=SC1090,SC2154
        source $AUTOMATION_LIB_PATH/$libname.sh
    done

    # Shortcuts to common retry/timeout calls
    lilto() { err_retry 8 1000 "" "$@"; }  # just over 4 minutes max
    bigto() { err_retry 7 5670 "" "$@"; }  # 12 minutes max
else  # Automation common library not installed yet
    echo "Warning: Automation library not found. Assuming it's not yet installed" \
        > /dev/stderr
    die() { echo "ERROR: ${1:-No error message provided}"; exit 1; }
fi

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
    # TODO: Look up the kube RPM/DEB version installed, or in $PACKAGE_DOWNLOAD_DIR
    #       and retrieve the major-minor version directly.
    local KUBERNETES_VERSION="1.15"
    echo "$KUBERNETES_VERSION"
}

# Warning: DO NOT USE these functions willy-nilly!
# They are only intended to be called by other setup scripts, as the very
# last step during the build process.  They're purpose is to "reset" the
# VM so all the first-boot operations happen again normally (like
# generating new ssh host keys, resizing partitions, etc.)
common_finalize() {
    cd /
    $SUDO cloud-init clean --logs
    $SUDO rm -rf $SCRIPT_DIRPATH
    $SUDO rm -rf /var/lib/cloud/instanc*
    $SUDO rm -rf /root/.ssh/*
    $SUDO rm -rf /etc/ssh/*key*
    $SUDO rm -rf /etc/ssh/moduli
    $SUDO rm -rf /home/*
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
