#!/usr/bin/env bash

# This script is set as, and intended to run as the `imgprune` container's
# entrypoint.  It is largely based on the imgobsolete's entrypoint script
# but with some important/subtle differences.  It searches for deprecated
# VM images with deletion-metadata some time in the past.  Some number of
# these images are randomly selected and then permanently deleted.

set -e

# shellcheck source=imgts/lib_entrypoint.sh
source /usr/local/bin/lib_entrypoint.sh

req_env_vars GCPJSON GCPNAME GCPPROJECT AWSINI IMG_SFX

gcloud_init

# Set this to 1 for testing
DRY_RUN="${DRY_RUN:-0}"
# For safety's sake limit nr deletions
DELETE_LIMIT=50
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

msg "Searching for obsolete GCP images using filter:${NOR} $FILTER"
# Ref: https://cloud.google.com/compute/docs/images/create-delete-deprecate-private-images#deprecating_an_image
$GCLOUD compute images list --show-deprecated \
    --format="$FORMAT" --filter="$FILTER" | \
    while read name selfLink dep_state del_date labels
    do
        count_image
        reason=""
        permanent=$(grep -E --only-matching --max-count=1 --ignore-case 'permanent=true' <<< $labels || true)
        [[ -z "$permanent" ]] || \
            die 1 "Refusing to delete a deprecated image labeled permanent=true.  Please use gcloud utility to set image active, then research the cause of deprecation."
        [[ "$dep_state" == "OBSOLETE" ]] || \
            die 1 "Unexpected depreciation-state encountered for $name: $dep_state; labels: $labels"

        # Any image matching the currently in-use IMG_SFX must always be preserved.
        # Values are defined in cirrus.yml
        # shellcheck disable=SC2154
        if [[ "$name" =~ $IMG_SFX ]]; then
            msg "    Skipping current (latest) image $name"
            continue
        fi

        reason="Obsolete as of $del_date; labels: $labels"
        echo "GCP $name $reason" >> $TODELETE
    done

msg "Searching for deprecated EC2 images prior to${NOR} $ABOUTNOW"
aws_init

# The AWS cli returns a huge blob of data we mostly don't need.
# # Use query statement to simplify the results.  N/B: The get_tag_value()
# # function expects to find a "TAGS" item w/ list value.
ami_query='Images[*].{ID:ImageId,TAGS:Tags,DEP:DeprecationTime,SNAP:BlockDeviceMappings[0].Ebs.SnapshotId}'
all_amis=$($AWS ec2 describe-images --owners self --query "$ami_query")
nr_amis=$(jq -r -e length<<<"$all_amis")

req_env_vars all_amis nr_amis
for (( i=nr_amis ; i ; i-- )); do
    count_image
    unset ami ami_id dep snap permanent
    ami=$(jq -r -e ".[$((i-1))]"<<<"$all_amis")
    ami_id=$(jq -r -e ".ID"<<<"$ami")
    dep=$(jq -r -e ".DEP"<<<"$ami")
    if [[ "$dep" == null ]] || [[ -z "$dep" ]]; then continue; fi
    dep_ymd=$(date --date="$dep" --iso-8601=date)
    snap=$(jq -r -e ".SNAP"<<<$ami)

    if permanent=$(get_tag_value "permanent" "$ami") && \
       [[ "$permanent" == "true" ]]
    then
        warn 0 "Found permanent image '$ami_id' with deprecation '$dep_ymd'.  Clearing deprecation date."
        $AWS ec2 disable-image-deprecation --image-id "$ami_id" > /dev/null
        continue
    fi

    unset name
    if ! name=$(get_tag_value "Name" "$ami"); then
        warn 0 "    EC2 AMI ID '$ami_id' is missing a 'Name' tag"
    fi

    # Any image matching the currently in-use IMG_SFX
    # must always be preserved.
    if [[ "$name" =~ $IMG_SFX ]]; then
        warn 0 "    Retaining current (latest) image $name id $ami_id"
        $AWS ec2 disable-image-deprecation --image-id "$ami_id" > /dev/null
        continue
    fi

    if [[ $(echo -e "$ABOUTNOW\n$dep_ymd" | sort | tail -1) == "$ABOUTNOW" ]]; then
      reason="Obsolete as of '$dep_ymd'; snap=$snap"
      echo "EC2 $ami_id $reason" >> $TODELETE
    fi
done

COUNT=$(<"$IMGCOUNT")
CANDIDATES=$(wc -l <$TODELETE)
msg "########################################################################"
msg "Deleting up to $DELETE_LIMIT random image candidates ($CANDIDATES/$COUNT total)::"

# Require a minimum number of images to exist
if [[ "$CANDIDATES" -lt $DELETE_LIMIT ]]
then
    die 0 "Safety-net Insufficient images ($CANDIDATES) to process deletions ($DELETE_LIMIT required)"
fi

sort --random-sort $TODELETE | tail -$DELETE_LIMIT | \
    while read -r cloud image_name reason; do

    msg "Deleting $cloud $image_name:${NOR} $reason"
    if ((DRY_RUN)); then
        msg "Dry-run: No changes made"
    elif [[ "$cloud" == "GCP" ]]; then
        $GCLOUD compute images delete $image_name
    elif [[ "$cloud" == "EC2" ]]; then
        # Snapshot ID's always start with 'snap-' followed by a hexadecimal string
        snap_id=$(echo "$reason" | sed -r -e 's/.* snap=(snap-[a-f0-9]+).*/\1/')
        [[ -n "$snap_id" ]] || \
            die 1 "Failed to parse EC2 snapshot ID for '$image_name' from string: '$reason'"
        # Because it aims to be as helpful and useful as possible, not all failure conditions
        # result in a non-zero exit >:(
        unset output
        output=$($AWS ec2 deregister-image --image-id "$image_name")
        [[ ! "$output" =~ An\ error\ occurred ]] || \
          die 1 "$output"

        msg " ...deleting snapshot $snap_id:${NOR} (formerly used by $image_name)"
        output=$($AWS ec2 delete-snapshot --snapshot-id "$snap_id")
        [[ ! "$output" =~ An\ error\ occurred ]] || \
          die 1 "$output"
    else
        die 1 "Unknown/Unsupported cloud '$cloud' record encountered in \$TODELETE file"
    fi
done
