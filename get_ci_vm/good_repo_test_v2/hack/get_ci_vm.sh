#!/usr/bin/env bash

#
# This file is used by the integration testing scripts,
# it should never be used under any other circumstance.

set -eu

in_get_ci_vm() {
    # shellcheck disable=SC2154
    if ((GET_CI_VM==0)); then
        echo "Error: $1 is not intended for use in this context"
        exit 2
    fi
}

# get_ci_vm APIv1 container entrypoint calls into this script
# to obtain required repo. specific configuration options.
if [[ "$1" == "--config" ]]; then
    case "$GET_CI_VM" in
        1)
            cat <<EOF
DESTDIR="/var/tmp/automation_images"
UPSTREAM_REPO="https://github.com/containers/automation_images.git"
CI_ENVFILE="/etc/automation_environment"
GCLOUD_PROJECT="automation_images"
GCLOUD_IMGPROJECT="automation_images"
GCLOUD_CFG="automation_images"
GCLOUD_ZONE="${GCLOUD_ZONE:-us-central1-a}"
GCLOUD_CPUS="0"
GCLOUD_MEMORY="0Gb"
GCLOUD_DISK="0"
EOF
            ;;
        2)
            # get_ci_vm APIv2 configuration details
            echo "AWS_PROFILE=automation_images"
            ;;
        *)
            echo "Error: Your get_ci_vm container image is too old."
            ;;
    esac
elif [[ "$1" == "--setup" ]]; then
    if ((GET_CI_VM==1)); then
        echo "I would have run some APIv1 repo. specific setup commands"
    elif ((GET_CI_VM==2)); then
        echo "I would have run some APIv2 repo. specific setup commands"
    else
        echo "Something is badly broken"
        exit 1
    fi
else
    echo "I would have executed podman run ... quay.io/libpod/get_ci_vm.sh \$@"
fi
