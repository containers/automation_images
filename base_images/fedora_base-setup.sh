#!/bin/bash

# This script is intended to be run by packer, inside a a Fedora VM.
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

# When installing during a container-build, installing anything
# selinux-related will seriously screw up the rest of your day
# with rpm debugging.
# Ref: https://github.com/rpm-software-management/rpm/commit/8cbe8baf9c3ff4754369bcd29441df14ecc6889d
declare -a PKGS
PKGS=(rng-tools git coreutils)
XSELINUX=
if ((CONTAINER)); then
    XSELINUX="--exclude=selinux*"
else
    PKGS+=(google-compute-engine-tools google-compute-engine-oslogin)
fi

dnf -y update $XSELINUX
dnf -y install $XSELINUX "${PKGS[@]}"

if ! ((CONTAINER)); then
    systemctl enable rngd
fi

install_automation_tooling

# There is a race that can happen on boot between the GCE services configuring
# the VM, and cloud-init trying to do similar activities.  Use a customized
# unit file to make sure cloud-init starts after the google-compute-* services.
cp -v $SCRIPT_DIRPATH/fedora-cloud-init.service /etc/systemd/system/

if ! ((CONTAINER)); then
    # ref: https://cloud.google.com/compute/docs/startupscript
    # The mechanism used by Cirrus-CI to execute tasks on the system is through an
    # "agent" process launched as a GCP startup-script (from the metadata service).
    # This agent is responsible for cloning the repository and executing all task
    # scripts and other operations.  Therefor, on SELinux-enforcing systems, the
    # service must be labeled properly to ensure it's child processes can
    # run with the proper contexts.
    METADATA_SERVICE_CTX=unconfined_u:unconfined_r:unconfined_t:s0
    METADATA_SERVICE_PATH=systemd/system/google-startup-scripts.service
    sed -r -e \
        "s/Type=oneshot/Type=oneshot\nSELinuxContext=$METADATA_SERVICE_CTX/" \
        /lib/$METADATA_SERVICE_PATH > /etc/$METADATA_SERVICE_PATH
fi

if [[ "$OS_RELEASE_ID" == "fedora" ]] && ((OS_RELEASE_VER>=33)); then
    # Ref: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=783509
    echo "Disabling automatic /tmp (tmpfs) mount"
    $SUDO systemctl mask tmp.mount
fi

finalize
