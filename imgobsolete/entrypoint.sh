#!/usr/bin/env bash

# This script is set as, and intended to run as the `imgobsolete` container's
# entrypoint.  It searches for non-deprecated VM images with missing/invalid
# metadata and those with an "old" `last-used` timestamp.  Some number of
# these images are randomly selected and made obsolete.   They are also
# marked with deletion-metadata some time in the future.

set -e

# shellcheck source=imgts/lib_entrypoint.sh
source /usr/local/bin/lib_entrypoint.sh

req_env_var GCPJSON GCPNAME GCPPROJECT

gcloud_init

# Set this to 1 for testing
DRY_RUN="${DRY_RUN:-0}"
OBSOLETE_LIMIT=10
THEFUTURE=$(date --date='+1 hour' +%s)
TOO_OLD='30 days ago'
THRESHOLD=$(date --date="$TOO_OLD" +%s)
# Format Ref: https://cloud.google.com/sdk/gcloud/reference/topic/formats
FORMAT='value[quote](name,selfLink,creationTimestamp,status,labels)'
# Required variable set by caller
# shellcheck disable=SC2154
PROJRE="/v1/projects/$GCPPROJECT/global/"
# Filter Ref: https://cloud.google.com/sdk/gcloud/reference/topic/filters
# shellcheck disable=SC2154
FILTER="selfLink~$PROJRE AND creationTimestamp<$(date --date="$TOO_OLD" --iso-8601=date)"
TOOBSOLETE=$(mktemp -p '' toobsolete.XXXXXX)

msg "Searching images for candidates using filter:${NOR} $FILTER"
# Ref: https://cloud.google.com/compute/docs/images/create-delete-deprecate-private-images#deprecating_an_image
$GCLOUD compute images list --format="$FORMAT" --filter="$FILTER" | \
    while read name selfLink creationTimestamp status labels
    do
        count_image
        reason=""
        created_ymd=$(date --date=$creationTimestamp --iso-8601=date)
        last_used=$(egrep --only-matching --max-count=1 'last-used=[[:digit:]]+' <<< $labels || true)

        LABELSFX="labels: '$labels'"

        # No label was set
        if [[ -z "$last_used" ]]
        then # image lacks any tracking labels
            reason="Missing 'last-used' metadata; $LABELSFX"
            echo "$name $reason" >> $TOOBSOLETE
            continue
        fi

        last_used_timestamp=$(date --date=@$(cut -d= -f2 <<< $last_used || true) +%s || true)
        last_used_ymd=$(date --date=@$last_used_timestamp --iso-8601=date)
        # Validate label contents
        if [[ -z "$last_used_timestamp" ]] || \
           [[ "$last_used_timestamp" -ge "$THEFUTURE" ]]
        then
            reason="Missing/invalid last-used timestamp: '$last_used_timestamp'; $LABELSFX"
            echo "$name $reason" >> $TOOBSOLETE
            continue
        fi

        # Image is actually too old
        if [[ "$last_used_timestamp" -le $THRESHOLD ]]
        then
            reason="Used over $TOO_OLD on $last_used_ymd; $LABELSFX"
            echo "$name $reason" >> $TOOBSOLETE
            continue
        fi

        msg "Retaining $name | $created_ymd | $status | $labels"
    done

COUNT=$(<"$IMGCOUNT")
msg "########################################################################"
msg "Obsoleting $OBSOLETE_LIMIT random images of $COUNT examined:"

# Require a minimum number of images to exist
if [[ "$COUNT" -lt $OBSOLETE_LIMIT ]]
then
    die 0 "Safety-net Insufficient images ($COUNT) to process ($OBSOLETE_LIMIT required)"
fi

sort --random-sort $TOOBSOLETE | tail -$OBSOLETE_LIMIT | \
    while read -r image_name reason; do

    msg "Obsoleting $image_name:${NOR} $reason"
    if ((DRY_RUN)); then
        msg "Dry-run: No changes made"
    else
        # Ref: https://cloud.google.com/compute/docs/images/create-delete-deprecate-private-images#deprecating_an_image
        $GCLOUD compute images deprecate $image_name --state=OBSOLETE --delete-in=30d
    fi
done
