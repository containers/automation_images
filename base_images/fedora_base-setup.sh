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

# Update to Rawhide
# NOTE: Should not break Fedora releases
if [[ -z BUILD_RAWHIDE ]]; then
    $SUDO dnf -qqy distro-sync --releasever=rawhide --allowerasing
fi

declare -a PKGS
PKGS=(rng-tools git coreutils cloud-init)
XARGS=--disablerepo=updates
if ! ((CONTAINER)); then
    # Packer defines this automatically for us
    # shellcheck disable=SC2154
    if [[ "$PACKER_BUILD_NAME" =~ "aws" ]]; then
        echo "WARN: AWS EC2 Instance Connect not supported on Fedora, use cloud-init."
        PKGS+=(policycoreutils-python-utils policycoreutils)
    else  # GCP image
        PKGS+=(google-compute-engine-oslogin)
        if ((OS_RELEASE_VER<35)); then
            PKGS+=(google-compute-engine-tools)
        else
            PKGS+=(google-compute-engine-guest-configs)
        fi
    fi
fi

# Due to https://bugzilla.redhat.com/show_bug.cgi?id=1907030
# updates cannot be installed or even looked at during this stage.
# Pawn the problem off to the cache-image stage where more memory
# is available and debugging is also easier.  Try to save some more
# memory by pre-populating repo metadata prior to any transactions.
$SUDO dnf makecache $XARGS
# Updates disable, see comment above
# $SUDO dnf -y update $XARGS
$SUDO dnf -y install $XARGS "${PKGS[@]}"

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

    # The mechanism used by Cirrus-CI to execute tasks on the system is through an
    # "agent" process launched as a GCP VM startup-script (from 'user-data').
    # This agent is responsible for cloning the repository and executing all task
    # scripts and other operations.  Therefor, on SELinux-enforcing systems, the
    # service must be labeled properly to ensure it's child processes can
    # run with the proper contexts.
    METADATA_SERVICE_CTX=unconfined_u:unconfined_r:unconfined_t:s0
    if [[ "$PACKER_BUILD_NAME" =~ "aws" ]]; then
        echo "Setting AWS startup service (for Cirrus-CI agent) SELinux unconfined"
        # AWS relies on cloud-init to run a user-data startup script.  Manual
        # observation showed this happens in the cloud-final service.
        METADATA_SERVICE_PATH=systemd/system/cloud-final.service
        # This is necessary to prevent permission-denied errors on service-start
        # and also on the off-chance the package gets updated and context reset.
        $SUDO semanage fcontext --add --type bin_t /usr/bin/cloud-init
        $SUDO restorecon -v /usr/bin/cloud-init
    else  # GCP Image
        echo "Setting GCP startup service (for Cirrus-CI agent) SELinux unconfined"
        # ref: https://cloud.google.com/compute/docs/startupscript
        METADATA_SERVICE_PATH=systemd/system/google-startup-scripts.service
    fi
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
