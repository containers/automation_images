#!/bin/bash

# This script is intended to be executed in the bench_stuff container by
# Cirrus-CI.  Any other usage or environment could lead to negative
# outcomes.

set -eo pipefail

SCRIPT_DIRPATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
source $SCRIPT_DIRPATH/../lib.sh

req_env_vars CIRRUS_CI

# No credentials required for dry-run mode (-d), but existing-file check needs
# to be bypassed.
export GOOGLE_APPLICATION_CREDENTIALS=/proc/cpuinfo

echo "Confirming error when no arguments given"
output=$(entrypoint.sh 2>&1 || true)
grep -q 'Must be called with the path to an existing search directory' <<<"$output"

echo "Confirming dry-run execution against dummy-data"
output=$(entrypoint.sh $SCRIPT_DIRPATH/test_data -v -d 2>&1)
declare -a expected
expected_lines=(\
    "Verbose-mode enabled"
    "Dry-run"
    "Loading environment"
    "Processing Basis"
    "Did NOT insert"
)
for expected in "${expected_lines[@]}"; do
    grep -q "$expected" <<<"$output" || \
      die "Did not find '$expected' in output: $output"
done
