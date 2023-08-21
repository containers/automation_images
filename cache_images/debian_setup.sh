#!/bin/bash

# This script is called by packer on the subject Debian VM, to setup the podman
# build/test environment.  It's not intended to be used outside of this context.

set -e

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

if ! ((CONTAINER)); then
    # Run as quickly as possible after boot
    /bin/bash $REPO_DIRPATH/systemd_banish.sh
fi

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# Generate en_US.UTF-8 locale as this is required for a podman test (https://github.com/containers/podman/pull/19635).
$SUDO sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen
$SUDO locale-gen

req_env_vars PACKER_BUILD_NAME

bash $SCRIPT_DIRPATH/debian_packaging.sh

if ! ((CONTAINER)); then
    warn "Making Debian kernel enable cgroup swap accounting"
    warn "Forcing CgroupsV1"
    SEDCMD='s/^GRUB_CMDLINE_LINUX="(.*)"/GRUB_CMDLINE_LINUX="\1 cgroup_enable=memory swapaccount=1 systemd.unified_cgroup_hierarchy=0"/'
    ooe.sh $SUDO sed -re "$SEDCMD" -i /etc/default/grub.d/*
    ooe.sh $SUDO sed -re "$SEDCMD" -i /etc/default/grub
    ooe.sh $SUDO update-grub
fi

nm_ignore_cni

finalize

echo "SUCCESS!"
