#!/bin/bash

# This script is called by packer on the subject Ubuntu VM, to setup the podman
# build/test environment.  It's not intended to be used outside of this context.

set -e

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# Run as quickly as possible after boot
/bin/bash $REPO_DIRPATH/systemd_banish.sh

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

bash $SCRIPT_DIRPATH/ubuntu_packaging.sh

echo "Making Ubuntu kernel to enable cgroup swap accounting as it is not the default."
SEDCMD='s/^GRUB_CMDLINE_LINUX="(.*)"/GRUB_CMDLINE_LINUX="\1 cgroup_enable=memory swapaccount=1"/g'
ooe.sh $SUDO sed -re "$SEDCMD" -i /etc/default/grub.d/*
ooe.sh $SUDO sed -re "$SEDCMD" -i /etc/default/grub
ooe.sh $SUDO update-grub

finalize

echo "SUCCESS!"
