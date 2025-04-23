#!/bin/bash

set -eo pipefail

# This script is intended to be used by Cirrus-CI, from the VM
# built by the 'image_builder' Makefile target in this repo.
# It's purpose is simply to verify & configure the runtime
# environment from data provided by CI, and call the make
# with the first argument passed to this script.

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# shellcheck disable=SC2154
if [[ -z "$CI" ]] || [[ "$CI" != "true" ]] || [[ "$CIRRUS_CI" != "$CI" ]]; then
    die "Unexpected \$CI=$CI and/or \$CIRRUS_CI=$CIRRUS_CI"
elif [[ -z "$IMG_SFX" ]] || [[ -z "$PACKER_BUILDS" ]]; then
    die "Required non-empty values for \$IMG_SFX=$IMG_SFX and \$PACKER_BUILDS=$PACKER_BUILDS"
elif [[ -z "$1" ]]; then
    die "Build stage name is required as the first argument"
fi

if skip_on_pr_label; then
    exit 0  # skip build
fi

set_gac_filepath

# Not all builds need this.
if [[ -n "$AWS_INI" ]]; then
    set_aws_filepath
fi

id
# FIXME: ssh-keygen seems to fail to create keys with Permission denied
# in the base_images make target, I have no idea why but all CI jobs are
# broken because of this. Let's try without selinux.
if [[ "$(getenforce)" == "Enforcing" ]]; then
    setenforce 0
fi

set -x
cd "$REPO_DIRPATH"
export IMG_SFX=$IMG_SFX
export PACKER_BUILDS=$PACKER_BUILDS
make ${1}
