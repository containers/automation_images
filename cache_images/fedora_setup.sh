#!/bin/bash

# This script is called by packer on the subject fedora VM, to setup the podman
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

# packer and/or a --build-arg define this envar value uniformly
# for both VM and container image build workflows.
req_env_vars PACKER_BUILD_NAME

bash $SCRIPT_DIRPATH/fedora_packaging.sh

if ! ((CONTAINER)); then
    msg "Enabling cgroup management from containers"
    ooe.sh $SUDO setsebool -P container_manage_cgroup true
fi

custom_cloud_init

# shellcheck disable=SC2154
if ! ((CONTAINER)) && [[ "$PACKER_BUILD_NAME" =~ prior ]]; then
    warn "Disabling CgroupsV2 kernel command-line option for systemd"
    SEDCMD='s/^GRUB_CMDLINE_LINUX="(.*)"/GRUB_CMDLINE_LINUX="\1 systemd.unified_cgroup_hierarchy=0"/'
    ooe.sh $SUDO sed -re "$SEDCMD" -i /etc/default/grub
    # This is always a symlink to the correct location under /boot/...
    ooe.sh $SUDO grub2-mkconfig -o $($SUDO realpath --physical /etc/grub2.cfg)
    # This is needed to update the /boot/loader/entries/... file to match grub
    # config (bug?).  Discovered Jul 28, 2021 on newly build F33 images.  Never
    # a problem before this point :(
    ooe.sh $SUDO grubby --grub2 --update-kernel=$($SUDO grubby --default-kernel) \
        --args="systemd.unified_cgroup_hierarchy=0"
fi

nm_ignore_cni

finalize

echo "SUCCESS!"
