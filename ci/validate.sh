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

req_env_vars CIRRUS_PR CIRRUS_PR_TITLE CIRRUS_USER_PERMISSION CIRRUS_BASE_BRANCH

show_env_vars

# die() will add a reference to this file and line number.
[[ "$CIRRUS_CI" == "true" ]] || \
  die "This script is only/ever intended to be run by Cirrus-CI."

# This is imperfect security-wise, but attempt to catch an accidental
# change in Cirrus-CI Repository settings.  Namely the hard-to-read
# "slider" that enables non-contributors to run jobs.  We don't want
# that on this repo, ever. because there are sensitive secrets in use.
# This variable is set by CI and validated non-empty above
# shellcheck disable=SC2154
if [[ "$CIRRUS_USER_PERMISSION" != "write" ]] && [[ "$CIRRUS_USER_PERMISSION" != "admin" ]]; then
  die "CI Execution not supported with permission level '$CIRRUS_USER_PERMISSION'"
fi

for target in image_builder/gce.json base_images/cloud.json \
              cache_images/cloud.json win_images/win-server-wsl.json; do
  if ! make $target; then
    die "Running 'make $target' failed, please validate input YAML files."
  fi
done

### The following checks only apply if validating a PR
if [[ -z "$CIRRUS_PR" ]]; then
  echo "Not validating IMG_SFX changes outside of a PR"
  exit 0
fi

# For Docs-only PRs, no further checks are needed
# Variable is defined by Cirrus-CI at runtime
# shellcheck disable=SC2154
if [[ "$CIRRUS_PR_TITLE" =~ CI:DOCS ]]; then
  msg "This looks like a docs-only PR, skipping further validation checks."
  exit 0
fi

# Fix "Not a valid object name main" error from Cirrus's
# incomplete checkout.
git remote update origin
# Determine where PR branched off of $CIRRUS_BASE_BRANCH
# shellcheck disable=SC2154
base_sha=$(git merge-base origin/${CIRRUS_BASE_BRANCH:-main} HEAD)

if ! git diff --name-only ${base_sha}..HEAD | grep -q IMG_SFX; then
  die "Every PR that builds images must include an updated IMG_SFX file.
Simply run 'make IMG_SFX', commit the result, and re-push."
else
  IMG_SFX="$(<./IMG_SFX)"
  # IMG_SFX was modified vs PR's base-branch, confirm version moved forward
  v_prev=$(git show ${base_sha}:IMG_SFX 2>&1 || true)
  # Verify new IMG_SFX value always version-sorts later than previous value.
  # This prevents screwups due to local timezone, bad, or unset clocks, etc.
  new_img_ver=$(awk -F 't' '{print $1"."$2}'<<<"$IMG_SFX" | cut -dz -f1)
  old_img_ver=$(awk -F 't' '{print $1"."$2}'<<<"$v_prev" | cut -dz -f1)
  # Version-sorting of date/time mimics the way renovate will compare values
  # see https://github.com/containers/automation/blob/main/renovate/defaults.json5
  latest_img_ver=$(echo -e "$new_img_ver\n$old_img_ver" | sort -V | tail -1)
  [[ "$latest_img_ver" == "$new_img_ver" ]] || \
    die "Updated IMG_SFX '$IMG_SFX' appears to be older than previous
value '$v_prev'.  Please check your local clock and try again."

  # IMG_SFX values need to change for every image build, even within the
  # same PR.  Attempt to catch re-use of a tag before starting the lengthy
  # build process (which will fail on a duplicate).  Check the imgts image
  # simply because it builds very early in cirrus-ci and cannot be skipped
  # with a "no_*" label.
  existing_tags=$(skopeo list-tags docker://quay.io/libpod/imgts | jq -r -e '.Tags[]')
  if grep -q "$IMG_SFX" <<<"$existing_tags"; then
    echo "It's highly likely the IMG_SFX '$IMG_SFX' is being re-used."
    echo "Don't do this.  Run 'make IMG_SFX', commit the result, and re-push".
    exit 1
  fi
fi
