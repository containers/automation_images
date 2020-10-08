#!/bin/bash

# This script is called by packer on the subject fedora VM, to setup the podman
# build/test environment.  It's not intended to be used outside of this context.

set -e

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# Run as quickly as possible after boot
/bin/bash $REPO_DIRPATH/systemd_banish.sh

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# Do not enable updates-testing on the previous Fedora release
# (packer defines this envar)
# shellcheck disable=SC2154
if [[ "$PACKER_BUILD_NAME" =~ prior ]]; then
    ENABLE_UPDATES_TESTING=0
else
    ENABLE_UPDATES_TESTING=1
fi

# TODO: Remove this once crun-0.15-5 moves into updates from updates-testing
ENABLE_UPDATES_TESTING=1

bash $SCRIPT_DIRPATH/fedora_packaging.sh

echo "Enabling cgroup management from containers"
((CONTAINER)) || \
    ooe.sh $SUDO setsebool -P container_manage_cgroup true

custom_cloud_init

finalize

echo "SUCCESS!"
