#!/bin/bash

# This script is intended to be executed in the ccia container by
# Cirrus-CI.  Any other usage or environment could lead to negative
# outcomes.

set -eo pipefail

SCRIPT_DIRPATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
source $SCRIPT_DIRPATH/../lib.sh

req_env_vars CIRRUS_CI CIRRUS_BUILD_ID CIRRUS_WORKING_DIR

echo "Installing test tooling"
ooe.sh microdnf install -y coreutils jq

echo "Confirming current build task manifests can be downloaded."
(
    set -x
    cd /data
    # shellcheck disable=SC2154
    $CCIABIN --verbose $CIRRUS_BUILD_ID '.*/manifest.json'
)

echo "Confirming any downloaded manifests can be parsed into a build list"
(
    set -x
    cd /data
    find ./ -type f -name 'manifest.json' -print0 | \
        xargs --null jq -e '.builds[]' | \
        jq -e -s '.' | \
        jq -e '{"builds": .}'
)
