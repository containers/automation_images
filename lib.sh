

# This file is intended to be sourced by other scripts running on
# aa Fedora or Ubuntu VM during various stages of initial setup.
# Using it in any other way or context unlikely to do anything
# useful for you.

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")

SUDO=""
[[ "$UID" -eq 0 ]] || \
    SUDO="sudo"

OS_RELEASE_VER="$(source /etc/os-release; echo $VERSION_ID | cut -d '.' -f 1)"
OS_RELEASE_ID="$(source /etc/os-release; echo $ID)"

SRC=$(realpath $(dirname "${BASH_SOURCE[0]}")/../)
CUSTOM_CLOUD_CONFIG_DEFAULTS="$SCRIPT_DIRPATH/cloud-init/$OS_RELEASE_ID/cloud.cfg.d"
# Avoid getting stuck waiting for user input
[[ "$OS_RELEASE_ID" != "ubuntu" ]] || \
    export DEBIAN_FRONTEND="noninteractive"

# This location is checked by automation in other repos, please do not change.
PACKAGE_DOWNLOAD_DIR=/var/cache/download

# TODO: Lock down to specific version number for stability
INSTALL_AUTOMATION_VERSION="latest"

# After install, automation common library function will define
if [[ $(type -t die) != 'function' ]]; then
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
    fi
    set +x;
    GAC_FILEPATH=$(mktemp -p '' '.XXXXXXXX.')
    export GAC_FILEPATH
    trap "rm -f $GAC_FILEPATH" EXIT
    echo "$GAC_JSON" > "$GAC_FILEPATH"
    unset GAC_JSON;
}

# Warning: DO NOT USE these functions willy-nilly!
# They are only intended to be called by other setup scripts, as the very
# last step during the build process.  They're purpose is to "reset" the
# VM so all the first-boot operations happen again normally (like
# generating new ssh host keys, resizing partitions, etc.)
common_finalize() {
    cd /
    $SUDO rm -rf $SCRIPT_DIRPATH
    $SUDO rm -rf /var/lib/cloud/instanc*
    $SUDO rm -rf /root/.ssh/*
    $SUDO rm -rf /etc/ssh/*key*
    $SUDO rm -rf /etc/ssh/moduli
    $SUDO rm -rf /home/*
    $SUDO rm -rf /tmp/*
    $SUDO rm -rf /tmp/.??*
    $SUDO sync
    $SUDO fstrim -av
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
    common_finalize
}

finalize() {
    case "$OS_RELEASE_ID" in
        fedora)
            rh_finalize
            ;;
        ubuntu)
            ubuntu_finalize
            ;;
    esac
}
