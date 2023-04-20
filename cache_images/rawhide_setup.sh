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

# Show what's happening
set -x

# Rawhide often has GPG issues, don't bother checking
$SUDO sed -i -r -e 's/^gpgcheck=.+/gpgcheck=False/' /etc/dnf/dnf.conf
$SUDO sed -i -r -e 's/^gpgcheck=.+/gpgcheck=0/' /etc/yum.repos.d/*.repo

$SUDO dnf -qqy distro-sync --releasever=rawhide --allowerasing
$SUDO dnf upgrade -y

$SUDO reboot
