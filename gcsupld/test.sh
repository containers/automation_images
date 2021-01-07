#!/bin/bash

# This script is only intended to be executed by Cirrus-CI in order
# to test the functionality of the freshly built gcsupld container.
# Any other usage is unlikely to function properly.

#Note: Assumed these are set properly in .cirrus.yml- $GCPJSON $GCPNAME $GCPPROJECT

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "$0")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# Guarantee the filename is unique per-test-run to prevent
# any clashes. Assume the bucket holding the test files will
# prune them regularly.
# shellcheck disable=SC2154
FROM_FILEPATH="testfile_${IMG_SFX}"
TO_GCSURI="gs://libpod-pr-releases/${FROM_FILEPATH}"

echo "Creating test-data file"
expected=$(date --iso-8601=seconds)
echo "$expected" > $FROM_FILEPATH

echo "Executing gcsupld entrypoint script"
output=$(/usr/local/bin/entrypoint.sh |& tee /dev/stderr)
echo "(exit $?)"

echo "Confirming gsutil reported 'Operation Completed'"
grep -iq 'operation completed'<<<"$output"

echo "Confirming the URL to download the file was output by entrypoint script"
actual_uri=$(tail -3<<<"$output" | grep -Exo -m 1 '\s+https://.+' | tr -d '[:blank:]' )
test -n "$actual_uri"

echo "Downloading contents of '$actual_uri'"
actual=$(curl --silent --location --fail "$actual_uri")

echo "Confirming downloaded data matches expectations"
set -x
test "$expected" == "$actual"
