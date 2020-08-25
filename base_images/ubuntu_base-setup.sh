#!/bin/bash

# This script is intended to be run by packer, inside a a Fedora VM.
# It's purpose is to configure the VM for importing into google cloud,
# so that it will boot in GCE and be accessable for further use.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# Run as quickly as possible after boot
/bin/bash $REPO_DIRPATH/systemd_banish.sh

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

set -x  # simpler than echo'ing each operation
$SUDO apt-get -qq -y update
if [[ "$OS_RELEASE_ID" -lt 20 ]]; then
    # Gets stuck on upgrade, even with DEBIAN_FRONTEND="noninteractive"
    $SUDO apt-mark hold 'openssh-server'
fi
$SUDO apt-get -qq -y upgrade
if [[ "$OS_RELEASE_ID" -lt 20 ]]; then
    $SUDO apt-mark unhold 'openssh-server'
fi
$SUDO apt-get -qq -y install software-properties-common git curl

# Install common automation tooling (i.e. ooe.sh)
curl --silent --show-error --location \
     --url "https://raw.githubusercontent.com/containers/automation/master/bin/install_automation.sh" | \
     $SUDO env INSTALL_PREFIX=/usr/share /bin/bash -s - "$INSTALL_AUTOMATION_VERSION"

finalize
