#!/usr/bin/env bash

# This script is set as, and intended to run as the `imgprune` container's
# entrypoint.  It is largely based on the imgobsolete's entrypoint script
# but with some important/subtle differences.  It searches for deprecated
# VM images with deletion-metadata some time in the past.  Some number of
# these images are randomly selected and then permanently deleted.

set -e

# shellcheck source=imgts/lib_entrypoint.sh
source /usr/local/bin/lib_entrypoint.sh

req_env_vars GCPJSON GCPNAME GCPPROJECT

gcloud_init

# Set this to 1 for testing
DRY_RUN="${DRY_RUN:-0}"
# For safety's sake limit nr deletions
DELETE_LIMIT=10
ABOUTNOW=$(date --iso-8601=date)  # precision is not needed for this use
# Format Ref: https://cloud.google.com/sdk/gcloud/reference/topic/formats
# Field list from `gcloud compute images list --limit=1 --format=text`
FORMAT='value[quote](name,selfLink,deprecated.state,deprecated.deleted,labels)'
# Required variable set by caller
# shellcheck disable=SC2154
PROJRE="/v1/projects/$GCPPROJECT/global/"
# Filter Ref: https://cloud.google.com/sdk/gcloud/reference/topic/filters
# Note: deprecated.delete comes from --delete-in (from imgobsolete container)
FILTER="selfLink~$PROJRE AND deprecated.state=OBSOLETE AND deprecated.deleted<$ABOUTNOW"
TODELETE=$(mktemp -p '' todelete.XXXXXX)

msg "Searching for obsolete images using filter:${NOR} $FILTER"
# Ref: https://cloud.google.com/compute/docs/images/create-delete-deprecate-private-images#deprecating_an_image
$GCLOUD compute images list --show-deprecated \
    --format="$FORMAT" --filter="$FILTER" | \
    while read name selfLink dep_state del_date labels
    do
        count_image
        reason=""
        permanent=$(egrep --only-matching --max-count=1 --ignore-case 'permanent=true' <<< $labels || true)
        [[ -z "$permanent" ]] || \
            die 1 "Refusing to delete a deprecated image labeled permanent=true.  Please use gcloud utility to set image active, then research the cause of deprecation."
        [[ "$dep_state" == "OBSOLETE" ]] || \
            die 1 "Unexpected depreciation-state encountered for $name: $dep_state; labels: $labels"
        reason="Obsolete as of $del_date; labels: $labels"
        echo "$name $reason" >> $TODELETE
    done

COUNT=$(<"$IMGCOUNT")
msg "########################################################################"
msg "Deleting up to $DELETE_LIMIT random images of $COUNT examined:"

# Require a minimum number of images to exist
if [[ "$COUNT" -lt $DELETE_LIMIT ]]
then
    die 0 "Safety-net Insufficient images ($COUNT) to process deletions ($DELETE_LIMIT required)"
fi

sort --random-sort $TODELETE | tail -$DELETE_LIMIT | \
    while read -r image_name reason; do

    msg "Deleting $image_name:${NOR} $reason"
    if ((DRY_RUN)); then
        msg "Dry-run: No changes made"
    else
        $GCLOUD compute images delete $image_name
    fi
done
