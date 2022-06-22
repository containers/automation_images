#!/bin/bash

# This script is intended to be used by Cirrus-CI, from the VM
# built by the 'image_builder' makefile target in this repo.  Use
# of this script in any other context/environment is unlikely to
# function as intended.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# shellcheck disable=SC2154
if [[ "$CI" != "true" ]] || [[ "$CIRRUS_CI" != "$CI" ]]; then
    die "Unexpected \$CI='$CI' and/or \$CIRRUS_CI='$CIRRUS_CI'"
fi

declare -a req_vars
req_vars=(\
    IMG_SFX
    TARGET_NAME
    DEST_FQIN
    REG_USERNAME
    REG_PASSWORD
    TEMPDIR
)
for req_var in "${req_vars[@]}"; do
    if [[ -z "${!req_var}" ]]; then
        echo "ERROR: Required variable \$$req_var is unset or empty."
        exit 1
    fi
done

# These both come in from Cirrus-CI
# shellcheck disable=SC2154
SRC_FQIN="$TARGET_NAME:$IMG_SFX"

make "$TARGET_NAME" IMG_SFX=$IMG_SFX

# Cirrus-CI will try to collect up the package cache, but fails
# on special files (like gpg agent sockets).  Remove them.
echo "Clearing special files from package cache"
# shellcheck disable=SC2154
find $TEMPDIR/.cache -type s -exec rm -vf '{}' +

# Prevent pushing 'latest' images from PRs, only branches and tags
# shellcheck disable=SC2154
if [[ $PUSH_LATEST -eq 1 ]] && [[ -n "$CIRRUS_PR" ]]; then
    echo -e "\nWarning: Refusing to push 'latest' images when testing from a PR.\n"
    PUSH_LATEST=0
fi

# Don't leave credential file sticking around anywhere
trap "podman logout --all" EXIT INT CONT
set +x  # protect username/password values
# These both come in from Cirrus-CI
# shellcheck disable=SC2154
echo "$REG_PASSWORD" | \
    podman login --password-stdin --username "$REG_USERNAME" "${DEST_FQIN%%:*}"

set -x  # Easier than echo'ing out status for everything
# DEST_FQIN comes in from Cirrus-CI
# shellcheck disable=SC2154
podman tag "$SRC_FQIN" "$DEST_FQIN"
podman push "$DEST_FQIN"

if ((PUSH_LATEST)); then
    LATEST_FQIN="${DEST_FQIN%:*}:latest"
    podman tag "$SRC_FQIN" "$LATEST_FQIN"
    podman push "$LATEST_FQIN"
fi
