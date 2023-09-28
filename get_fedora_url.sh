#!/bin/bash

# This script is intended to be called by the Makefile, not by
# humans.  This implies certain otherwise "odd" behaviors, such
# as exiting with no std-output if there was an error.  It expects
# to be called with three arguments:
# 1. The type of url to retrieve, `image` or `checksum`.
# 2. The architecture, `x86_64` or `aarch64`
# 3. The Fedora release, 'rawhide' or a release number.

set -eo pipefail

URL_BASE="https://dl.fedoraproject.org/pub/fedora/linux"
CURL="curl --location --silent --fail --show-error"

url_type="$1"
arch_name="$2"
fed_rel="$3"

die() { echo "ERROR: ${1:-No error message provided}" > /dev/stderr; exit 1; }

msg() { echo "${1:-No error message provided}" > /dev/stderr; }

usage_sfx="<image|checksum> <x86_64|aarch64> <release #>"

[[ "$#" -eq 3 ]] || \
    die "Expecting exactly 3 arguments: $usage_sfx"

tmpfile=$(mktemp -p '' tmp.$(basename ${BASH_SOURCE[0]}).XXXX)
trap "rm -f $tmpfile" EXIT

stage_tree="development"
if  [[ "$fed_rel" != "rawhide" ]] && \
    $CURL "${URL_BASE}/releases/$fed_rel" &>/dev/null
then
    stage_tree="releases"
fi

cloud_download_url="${URL_BASE}/$stage_tree/$fed_rel/Cloud/$arch_name/images"
dbg_msg_sfx="'$arch_name' arch Fedora '$fed_rel' release '$url_type' from '$cloud_download_url'"

# Show usage again to help catch argument order / spelling mistakes.
$CURL -o "$tmpfile" "$cloud_download_url" || \
    die "Fetching download listing for $dbg_msg_sfx.
Was argument form valid: $usage_sfx"

targets=$(sed -ne 's/^.*href=\"\(fedora[^\"]\+\)\".*$/\1/ip' <$tmpfile)
targets_oneline=$(tr -s '[:blank:]' ' '<<<"$targets")
[[ -n "$targets" ]] || \
    die "Did not find any fedora targets: $dbg_msg_sfx"

# Sometimes "rawhide" is spelled "Rawhide"
by_release=$(grep -iw "$fed_rel" <<<"$targets" || true)
[[ -n "$by_release" ]] || \
    die "Did not find target among '$targets_oneline)': $dbg_msg_sfx"

by_arch=$(grep -iw "$arch_name" <<<"$by_release" || true)
[[ -n "$by_arch" ]] || \
    die "Did not find arch among $by_release"

if [[ "$url_type" == "image" ]]; then
    extension=qcow2
elif [[ "$url_type" == "checksum" ]]; then
    extension=CHECKSUM
else
    die "Unknown/unsupported url type: '$url_type'."
fi

# Support both '.CHECKSUM' and '-CHECKSUM' at the end
filename=$(grep -E -i -m 1 -- "$extension$" <<<"$by_arch" || true)
[[ -n "$filename" ]] || \
    die "No '$extension' targets among $by_arch"

echo "$cloud_download_url/$filename"
