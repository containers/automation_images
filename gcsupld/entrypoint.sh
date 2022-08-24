#!/usr/bin/env bash

# This script is set as, and intended to run as the `gcsupld` container's
# entrypoint.  It simply authenticates to google cloud, then utilizes
# google-cloud-sdk utility to upload the file specified by `$FROM_FILENAME`
# to the bucket/object URI specified in `$TO_GCSURI`.

set -eo pipefail

# shellcheck source=imgts/lib_entrypoint.sh
source /usr/local/bin/lib_entrypoint.sh

req_env_vars GCPJSON GCPNAME GCPPROJECT FROM_FILEPATH TO_GCSURI

# shellcheck disable=SC2154
msg "Will upload '$FROM_FILEPATH' to '$TO_GCSURI'"

# shellcheck disable=SC2154
slash_count=$(tr -c -d '/'<<<"$TO_GCSURI" | wc -m)
# shellcheck disable=SC2154
if [[ ! -r "$FROM_FILEPATH" ]]; then
    die "Source file not found: $FROM_FILEPATH"
elif [[ -L "$FROM_FILEPATH" ]]; then
    die "Source file must not be a symlink: $FROM_FILEPATH"
elif [[ $slash_count -gt 3 ]]; then
    die "Subdirectories ($slash_count > 3) in destination filename not supported: $TO_GCSURI"
fi

gcloud_init

# The -e option needed to avoid uploading "empty" files
# The -c option needed to return error code on upload failure
gsutil cp -c -e "$FROM_FILEPATH" "$TO_GCSURI"

msg "Upload complete, file now available for download at:"
# term. codes present in displayed URI will break testing
echo "     https://storage.googleapis.com/${TO_GCSURI:5}"
