#!/usr/bin/env bash

#
# This file is used by the integration testing scripts,
# it should never be used under any other circumstance.
#
# get_ci_vm APIv1 container entrypoint calls into this script
# to obtain required repo. specific configuration options.
if [[ "$1" == "--config" ]]; then
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
elif [[ "$1" == "--setup" ]]; then
    echo "I would have run some repo. specific setup commands"
else
    echo "I would have executed podman run ... quay.io/libpod/get_ci_vm.sh \$@"
fi
