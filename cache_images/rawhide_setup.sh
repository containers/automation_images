#!/bin/bash

# This script is called by packer on the rawhide VM, to update and reboot using
# the rawhide kernel.  It's not intended to be used outside of this context.

set -e

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# packer and/or a --build-arg define this envar value uniformly
# for both VM and container image build workflows.
req_env_vars PACKER_BUILD_NAME

warn "Upgrading Fedora '$OS_RELEASE_VER' to rawhide, this might break."
# shellcheck disable=SC2154
warn "If so, this script may be found in the repo. as '$SCRIPT_DIRPATH/$SCRIPT_FILENAME'."

# Show what's happening
set -x

# Rawhide often has GPG issues, don't bother checking
$SUDO sed -i -r -e 's/^gpgcheck=.+/gpgcheck=False/' /etc/dnf/dnf.conf
$SUDO sed -i -r -e 's/^gpgcheck=.+/gpgcheck=0/' /etc/yum.repos.d/*.repo
# Called as `dnf5` here to confirm "old" dnf has been replaced.
$SUDO dnf5 -y distro-sync --releasever=rawhide --allowerasing
$SUDO dnf5 upgrade -y

# A shared fedora_packaging.sh script is called next that doesn't always support dnf5
$SUDO ln -s $(type -P dnf5) /usr/local/bin/dnf

# Packer will try to run 'cache_images/fedora_setup.sh' next, make sure the system
# is actually running rawhide (and verify it boots).
$SUDO reboot
