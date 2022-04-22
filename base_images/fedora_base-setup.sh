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
PKGS=(rng-tools git coreutils cloud-init)
XSELINUX=
if ((CONTAINER)); then
    if ((OS_RELEASE_VER<35)); then
        XSELINUX="--exclude=selinux*"
    fi
else
    PKGS+=(google-compute-engine-oslogin)
    if ((OS_RELEASE_VER<35)); then
        PKGS+=(google-compute-engine-tools)
    else
        PKGS+=(google-compute-engine-guest-configs)
    fi
fi

$SUDO dnf -y update $XSELINUX
$SUDO dnf -y install $XSELINUX "${PKGS[@]}"

if ! ((CONTAINER)); then
    $SUDO systemctl enable rngd
fi

install_automation_tooling

if ! ((CONTAINER)); then
    custom_cloud_init

    # Be kind to humans, indicate where generated files came from
    sourcemsg="### File generated during VM Image build by $(basename $SCRIPT_FILEPATH)"

    if ((OS_RELEASE_VER<35)); then
        echo "Overriding cloud-init service file"
        # The packaged cloud-init.service unit has a dependency loop
        # vs google-network-daemon.service.  Fix this with a custom
        # cloud-init service file.
        CLOUD_SERVICE_PATH="systemd/system/cloud-init.service"
        echo -e "$sourcemsg" | $SUDO tee /etc/$CLOUD_SERVICE_PATH
        cat $SCRIPT_DIRPATH/fedora-cloud-init.service | \
            $SUDO tee -a /etc/$CLOUD_SERVICE_PATH
    fi

    echo "Setting GCP startup service (for Cirrus-CI agent) SELinux unconfined"
    # ref: https://cloud.google.com/compute/docs/startupscript
    # The mechanism used by Cirrus-CI to execute tasks on the system is through an
    # "agent" process launched as a GCP startup-script (from the metadata service).
    # This agent is responsible for cloning the repository and executing all task
    # scripts and other operations.  Therefor, on SELinux-enforcing systems, the
    # service must be labeled properly to ensure it's child processes can
    # run with the proper contexts.
    METADATA_SERVICE_CTX=unconfined_u:unconfined_r:unconfined_t:s0
    METADATA_SERVICE_PATH=systemd/system/google-startup-scripts.service
    echo "$sourcemsg" | $SUDO tee -a /etc/$METADATA_SERVICE_PATH
    sed -r -e \
        "s/^Type=oneshot/Type=oneshot\nSELinuxContext=$METADATA_SERVICE_CTX/" \
        /lib/$METADATA_SERVICE_PATH | $SUDO tee -a /etc/$METADATA_SERVICE_PATH
fi

if [[ "$OS_RELEASE_ID" == "fedora" ]] && ((OS_RELEASE_VER>=33)); then
    # Ref: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=783509
    echo "Disabling automatic /tmp (tmpfs) mount"
    $SUDO systemctl mask tmp.mount
fi

finalize
