#!/bin/bash

# This script is intended to be run by packer, usage under any other
# environment may behave badly. Its purpose is to download a VM
# image and a checksum file. Verify the image's checksum matches.
# If it does, convert the downloaded image into the format indicated
# by the first argument's `.extension`.
#
# The first argument is the file path and name for the output image,
# the second argument is the image download URL (ending in a filename).
# The third argument is the download URL for a checksum file containing
# details necessary to verify vs filename included in image download URL.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

[[ "$#" -eq 3 ]] || \
    die "Expected to be called with three arguments, not: $#"

# Packer needs to provide the desired filename as it's unable to parse
# a filename out of the URL or interpret output from this script.
dest_dirpath=$(dirname "$1")
dest_filename=$(basename "$1")
dest_format=$(cut -d. -f2<<<"$dest_filename")
src_url="$2"
src_filename=$(basename "$src_url")
cs_url="$3"

req_env_vars dest_dirpath dest_filename dest_format src_url src_filename cs_url

mkdir -p "$dest_dirpath"
cd "$dest_dirpath"
[[ -r "$src_filename" ]] || \
    curl --fail --location -O "$src_url"
echo "Downloading & verifying checksums in $cs_url"
curl --fail --location "$cs_url" -o - | \
    sha256sum --ignore-missing --check -
echo "Converting '$src_filename' to ($dest_format format) '$dest_filename'"
qemu-img convert "$src_filename" -O "$dest_format" "${dest_filename}"
