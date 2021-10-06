#!/bin/bash

# This script is called by packer on the subject Ubuntu VM, to setup the podman
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

req_env_vars PACKER_BUILD_NAME

bash $SCRIPT_DIRPATH/ubuntu_packaging.sh

if ! ((CONTAINER)); then
    warn "Making Ubuntu kernel to enable cgroup swap accounting"
    SEDCMD='s/^GRUB_CMDLINE_LINUX="(.*)"/GRUB_CMDLINE_LINUX="\1 cgroup_enable=memory swapaccount=1'
    warn "Enabling CgroupsV2 kernel command-line option for systemd"
    SEDCMD="$SEDCMD systemd.unified_cgroup_hierarchy=1"
    SEDCMD="$SEDCMD\"/"
    ooe.sh $SUDO sed -re "$SEDCMD" -i /etc/default/grub.d/*
    ooe.sh $SUDO sed -re "$SEDCMD" -i /etc/default/grub
    ooe.sh $SUDO update-grub
fi

nm_ignore_cni

finalize

echo "SUCCESS!"
