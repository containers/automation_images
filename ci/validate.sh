#!/bin/bash

# This script is intended to be run by Cirrus-CI to validate PR
# content prior to building any images.  It should not be run
# under any other context.

set -eo pipefail

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

req_env_vars CIRRUS_PR CIRRUS_BASE_SHA

# die() will add a reference to this file and line number.
[[ "$CIRRUS_CI" == "true" ]] || \
  die "This script is only/ever intended to be run by Cirrus-CI."

for target in image_builder/gce.json base_images/cloud.json \
              cache_images/cloud.json win_images/win-server-wsl.json; do
  if ! make $target; then
    die "Running 'make $target' failed, please validate input YAML files."
  fi
done

# Variable is defined by Cirrus-CI at runtime
# shellcheck disable=SC2154
if ! git diff --name-only ${CIRRUS_BASE_SHA}..HEAD | grep -q IMG_SFX; then
  die "Every PR must include an updated IMG_SFX file.
Simply run 'make IMG_SFX', commit the result, and re-push."
fi

# Verify new IMG_SFX value always sorts later than previous value.  This prevents
# screwups due to local timezone, bad, or unset clocks, etc.
cd $REPO_DIRPATH
# Automation requires the date and time components sort properly
# as if they were version-numbers regardless of distro-version component.
new_img_ver=$(awk -F '-' '{print $1"."$2}' ./IMG_SFX)
# TODO: Conditional checkout not needed after the PR which added IMG_SFX file.
if git checkout ${CIRRUS_BASE_SHA} IMG_SFX; then
  old_img_ver=$(awk -F '-' '{print $1"."$2}' ./IMG_SFX)
  latest_img_ver=$(echo -e "$old_img_ver\n$new_img_ver" | sort -V | tail -1)
  [[ "$latest_img_ver" == "$new_img_ver" ]] || \
    die "Date/time stamp appears to have gone backwards! Please commit
an 'IMG_SFX' change with a value later than '$(<IMG_SFX)'"
else
  warn "Could not find previous version of IMG_SFX, ignoring."
fi
