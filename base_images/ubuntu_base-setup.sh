#!/bin/bash

# This script is intended to be run by packer, inside an Ubuntu VM.
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
$SUDO apt-get -qq -y upgrade apt dpkg
$SUDO apt-get -qq -y upgrade
$SUDO apt-get -qq -y install coreutils software-properties-common git curl openssh-server openssh-client

# Point sh at bash, system-wide.  This will slow boot-time but improve
# compatibility / usefullness of all automated scripting (which is bash-centric)
$SUDO DEBCONF_DB_OVERRIDE='File{'$SCRIPT_DIRPATH/no_dash.dat'}' \
    dpkg-reconfigure dash

# Install common automation tooling (i.e. ooe.sh)
curl --silent --show-error --location \
     --url "https://raw.githubusercontent.com/containers/automation/master/bin/install_automation.sh" | \
     $SUDO env INSTALL_PREFIX=/usr/share /bin/bash -s - "$INSTALL_AUTOMATION_VERSION"

finalize
