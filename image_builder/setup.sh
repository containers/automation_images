#!/bin/bash


# This script is called by packer on a vanilla CentOS VM, to setup the image
# used for building images FROM base images. It's not intended to be used
# outside of this context.

set -e

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# Run as quickly as possible after boot
# unless building a container
((CONTAINER)) || \
    /bin/bash $REPO_DIRPATH/systemd_banish.sh

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

PACKER_VERSION=$(bash $REPO_DIRPATH/get_packer_version.sh)
$SUDO env PACKER_VERSION=$PACKER_VERSION \
    /bin/bash "$SCRIPT_DIRPATH/install_packages.sh"

# Unnecessary inside a container
if ! ((CONTAINER)); then
    $SUDO systemctl enable rngd

    # Enable nested-virt
    $SUDO tee /etc/modprobe.d/kvm-nested.conf <<EOF
options kvm-intel nested=1
options kvm-intel enable_shadow_vmcs=1
options kvm-intel enable_apicv=1
options kvm-intel ept=1
EOF
fi

# This does lots of ugly stuff
finalize
