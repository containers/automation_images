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

cd /tmp/

echo "Confirming current build task manifests can be downloaded."
(
    set -x
    # shellcheck disable=SC2154
    $CCIABIN --verbose $CIRRUS_BUILD_ID '.*/manifest.json'
)

# It's possible the PR did not produce any manifest.json files
if ! dled=$(find ./$CIRRUS_BUILD_ID -name manifest.json | wc -l) || ((dled==0)); then
    mkdir -p ./$CIRRUS_BUILD_ID
    cp -a $SCRIPT_DIRPATH/fake_manifests/* ./$CIRRUS_BUILD_ID
fi

echo "Confirming any downloaded manifests can be parsed into a build list"
(
    set -x
    cd /tmp
    find ./$CIRRUS_BUILD_ID -type f -name 'manifest.json' -print0 | \
        xargs --null jq -e '.builds[]' | \
        jq -e -s '.' | \
        jq -e '{"builds": .}'
)
