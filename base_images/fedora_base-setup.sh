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

declare -a PKGS
PKGS=(rng-tools git coreutils cloud-init)
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
            PKGS+=(google-compute-engine-guest-configs google-guest-agent)
        fi
    fi
fi

# The Fedora CI VM base images are built using nested-virt with
# limited resources available.  Further, cloud-networking in
# general can sometimes be flaky.  Increase DNF's tolerance
# levels.
cat << EOF | $SUDO tee -a /etc/dnf/dnf.conf

# Added during CI VM image build
minrate=100
timeout=60
EOF

$SUDO dnf makecache
$SUDO dnf -y update
$SUDO dnf -y install "${PKGS[@]}"
# Occasionally following an install, there are more updates available.
# This may be due to activation of suggested/recommended dependency resolution.
$SUDO dnf -y update

if ! ((CONTAINER)); then
    $SUDO systemctl enable rngd
fi

install_automation_tooling

if ! ((CONTAINER)); then
    custom_cloud_init

    # Be kind to humans, indicate where generated files came from
    sourcemsg="### File generated during VM Image build by $(basename $SCRIPT_FILEPATH)"

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
        # This used restorecon before so we don't have to specify the file_contexts.local
        # manually, however with f42 that stopped working: https://bugzilla.redhat.com/show_bug.cgi?id=2360183
        $SUDO setfiles -v /etc/selinux/targeted/contexts/files/file_contexts.local /usr/bin/cloud-init
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

finalize
