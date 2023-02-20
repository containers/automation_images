#!/bin/bash

# This script is intended to be run by packer, inside an Debian VM.
# It's purpose is to configure the VM for importing into google cloud,
# so that it will boot in GCE and be accessable for further use.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# Run as quickly as possible after boot
/bin/bash $REPO_DIRPATH/systemd_banish.sh

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# Switch to Debian Unstable (SID)
cat << EOF | sudo tee /etc/apt/sources.list
deb http://deb.debian.org/debian/ unstable main
deb-src http://deb.debian.org/debian/ unstable main
EOF

declare -a PKGS
PKGS=( \
    coreutils
    curl
    cloud-init
    gawk
    git
    openssh-client
    openssh-server
    rng-tools5
    software-properties-common
)

echo "Updating package source lists"
$SUDO apt-get -qq -y update
echo "Upgrading to SID"
$SUDO apt-get -qq -y full-upgrade
echo "Installing basic, necessary packages."
$SUDO apt-get -qq -y install "${PKGS[@]}"

# compatibility / usefullness of all automated scripting (which is bash-centric)
$SUDO DEBCONF_DB_OVERRIDE='File{'$SCRIPT_DIRPATH/no_dash.dat'}' \
    dpkg-reconfigure dash

# Ref: https://wiki.debian.org/DebianReleases
# CI automation needs a *sortable* OS version/release number to select/perform/apply
# runtime configuration and workarounds.  Since switching to Unstable/SID, a
# numeric release version is not available. While an imperfect solution,
# base an artificial version off the 'base-files' package version, right-padded with
# zeros to ensure sortability (i.e. "12.02" < "12.13").
base_files_version=$(dpkg -s base-files | awk '/Version:/{print $2}')
base_major=$(cut -d. -f 1 <<<"$base_files_version")
base_minor=$(cut -d. -f 2 <<<"$base_files_version")
sortable_version=$(printf "%02d.%02d" $base_major $base_minor)
echo "WARN: This is NOT an official version number.  It's for CI-automation purposes only."
echo "VERSION_ID=\"$sortable_version\"" | \
    $SUDO tee -a /etc/os-release

install_automation_tooling

if ! ((CONTAINER)); then
    custom_cloud_init
    $SUDO systemctl enable rngd

    # Cloud-config fails to enable this for some reason or another
    $SUDO sed -i -r \
      -e 's/^PermitRootLogin no/PermitRootLogin prohibit-password/' \
      /etc/ssh/sshd_config
fi

finalize
