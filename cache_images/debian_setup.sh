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

# Debian doesn't mount tmpfs on /tmp as default but we want this to speed tests up so
# they don't have to write to persistent disk.
# https://github.com/containers/podman/pull/22533
$SUDO mkdir -p /etc/systemd/system/local-fs.target.wants/
cat <<EOF | $SUDO tee /etc/systemd/system/tmp.mount
[Unit]
Description=Temporary Directory /tmp
ConditionPathIsSymbolicLink=!/tmp
DefaultDependencies=no
Conflicts=umount.target
Before=local-fs.target umount.target
After=swap.target

[Mount]
What=tmpfs
Where=/tmp
Type=tmpfs
Options=size=75%%,mode=1777
EOF
# enable the unit by default
$SUDO ln -s ../tmp.mount /etc/systemd/system/local-fs.target.wants/tmp.mount

req_env_vars PACKER_BUILD_NAME

bash $SCRIPT_DIRPATH/debian_packaging.sh

if ! ((CONTAINER)); then
    warn "Making Debian kernel enable cgroup swap accounting"
    SEDCMD='s/^GRUB_CMDLINE_LINUX="(.*)"/GRUB_CMDLINE_LINUX="\1 cgroup_enable=memory swapaccount=1"/'
    ooe.sh $SUDO sed -re "$SEDCMD" -i /etc/default/grub.d/*
    ooe.sh $SUDO sed -re "$SEDCMD" -i /etc/default/grub
    ooe.sh $SUDO update-grub
fi

nm_ignore_cni

if ! ((CONTAINER)); then
    initialize_local_cache_registry
fi

finalize

echo "SUCCESS!"
