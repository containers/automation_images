#!/bin/bash

# This script is intended to be the entrypoint for the bench_stuff container image.
# Any other use is unlikely to function as intended.

set -e

source /etc/automation_environment
source $AUTOMATION_LIB_PATH/common_lib.sh

if [[ $# -lt 1 ]] || [[ ! -d "$1" ]]; then
    die "Must be called with the path to an existing search directory; Got '$1'."
fi

search_root="$1"
# Any additional arguments will be passed into the bench_stuff calls
shift

find "$search_root" -name benchmarks.env | \
    while read line; do
        data_dir=$(dirname "$line")
        bench_stuff "$@" "$data_dir"
    done
