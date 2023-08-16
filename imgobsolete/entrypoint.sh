#!/usr/bin/env bash

# This script is set as, and intended to run as the `imgobsolete` container's
# entrypoint.  It searches for non-deprecated VM images with missing/invalid
# metadata and those with an "old" `last-used` timestamp.  Some number of
# these images are randomly selected and made obsolete.   They are also
# marked with deletion-metadata some time in the future.

set -eo pipefail

# shellcheck source=imgts/lib_entrypoint.sh
source /usr/local/bin/lib_entrypoint.sh

req_env_vars GCPJSON GCPNAME GCPPROJECT AWSINI IMG_SFX IMPORT_IMG_SFX

gcloud_init

# Set this to 1 for testing
DRY_RUN="${DRY_RUN:-0}"
OBSOLETE_LIMIT=10
THEFUTURE=$(date --date='+1 hour' +%s)
TOO_OLD_DAYS='30'
TOO_OLD_DESC="$TOO_OLD_DAYS days ago"
THRESHOLD=$(date --date="$TOO_OLD_DESC" +%s)
# Format Ref: https://cloud.google.com/sdk/gcloud/reference/topic/formats
FORMAT='value[quote](name,selfLink,creationTimestamp,status,labels)'
# Required variable set by caller
# shellcheck disable=SC2154
PROJRE="/v1/projects/$GCPPROJECT/global/"
# Filter Ref: https://cloud.google.com/sdk/gcloud/reference/topic/filters
# shellcheck disable=SC2154
FILTER="selfLink~$PROJRE AND creationTimestamp<$(date --date="$TOO_OLD_DESC" --iso-8601=date)"
TOOBSOLETE=$(mktemp -p '' toobsolete.XXXXXX)

msg "${RED}Searching GCP images for candidates using filter: $FILTER"
# Ref: https://cloud.google.com/compute/docs/images/create-delete-deprecate-private-images#deprecating_an_image
$GCLOUD compute images list --format="$FORMAT" --filter="$FILTER" | \
    while read name selfLink creationTimestamp status labels
    do
        count_image
        reason=""
        created_ymd=$(date --date=$creationTimestamp --iso-8601=date)
        permanent=$(egrep --only-matching --max-count=1 --ignore-case 'permanent=true' <<< $labels || true)
        last_used=$(egrep --only-matching --max-count=1 'last-used=[[:digit:]]+' <<< $labels || true)

        LABELSFX="labels: '$labels'"

        # Any image marked with a `permanent=true` label should be retained forever.
        # Typically this will be due to it's use by CI in a release-branch.  The images
        # `repo-ref` and `build-id` labels should provide clues as to where it's
        # required (may be multiple repos.) - for any future auditing purposes.
        if [[ -n "$permanent" ]]; then
            msg "Retaining forever $name | $labels"
            continue
        fi

        # Any image matching the currently in-use IMG_SFX must always be preserved
        # Value is defined in cirrus.yml
        # shellcheck disable=SC2154
        if [[ "$name" =~ $IMG_SFX ]]; then
            msg "Retaining current (latest) image $name | $labels"
            continue
        fi

        # No label was set
        if [[ -z "$last_used" ]]
        then # image lacks any tracking labels
            reason="Missing 'last-used' metadata; $LABELSFX"
            echo "GCP $name $reason" >> $TOOBSOLETE
            continue
        fi

        last_used_timestamp=$(date --date=@$(cut -d= -f2 <<< $last_used || true) +%s || true)
        last_used_ymd=$(date --date=@$last_used_timestamp --iso-8601=date)
        # Validate label contents
        if [[ -z "$last_used_timestamp" ]] || \
           [[ "$last_used_timestamp" -ge "$THEFUTURE" ]]
        then
            reason="Missing/invalid last-used timestamp: '$last_used_timestamp'; $LABELSFX"
            echo "GCP $name $reason" >> $TOOBSOLETE
            continue
        fi

        # Image is actually too old
        if [[ "$last_used_timestamp" -le $THRESHOLD ]]
        then
            reason="Used over $TOO_OLD_DESC on $last_used_ymd; $LABELSFX"
            echo "GCP $name $reason" >> $TOOBSOLETE
            continue
        fi

        msg "Retaining $name | $created_ymd | $status | $labels"
    done


msg "${RED}Searching for obsolete EC2 images unused as of: ${NOR}$TOO_OLD_DESC"
aws_init

# The AWS cli returns a huge blob of data we mostly don't need.
# Use query statement to simplify the results.  N/B: The get_tag_value()
# function expects to find a "TAGS" item w/ list value.
ami_query='Images[*].{ID:ImageId,CREATED:CreationDate,STATE:State,TAGS:Tags,DEP:DeprecationTime}'
all_amis=$($AWS ec2 describe-images --owners self --query "$ami_query")
nr_amis=$(jq -r -e length<<<"$all_amis")

# For whatever reason, the last time the image was used is not
# provided in 'aws ec2 describe-images...' result, a separate
# command must be used.  For images without any `lastLaunchedTime`
# (lower-case l) attribute, the simple --query will return an
# empty-value and zero-exit instead of an absent key.
# N/B: The result data uses `LastLaunchedTime` (upper-case L) because
# AWS loves to keep us on our toes.
lltcmd=(\
     aws ec2 describe-image-attribute --attribute lastLaunchedTime
     --query "LastLaunchedTime" --image-id
)

req_env_vars all_amis nr_amis
for (( i=nr_amis ; i ; i-- )); do
    unset ami ami_id state created created_ymd name name_tag dep
    ami=$(jq -r -e ".[$((i-1))]"<<<"$all_amis")
    ami_id=$(jq -r -e ".ID"<<<"$ami")
    state=$(jq -r -e ".STATE"<<<"$ami")
    created=$(jq -r -e ".CREATED"<<<"$ami")
    created_ymd=$(date --date="$created" --iso-8601=date)
    dep=$(jq -r -e ".DEP"<<<"$ami")

    unset tags
    # The name-tag is easier on human eys if one is set.
    name="$ami_id"
    if name_tag=$(get_tag_value "Name" "$ami"); then
        name="$name_tag"
        tags="Name=$name_tag"
    fi

    for tag in permanent build-id repo-ref automation; do
        if [[ -z "$tags" ]]; then
            tags="$tag="
        else
            tags+=",$tag="
        fi

        unset tagval
        if tagval=$(get_tag_value "$tag" "$ami"); then
            tags+="$tagval"
        fi
    done

    unset automation permanent reason
    automation=$(egrep --only-matching --max-count=1 \
                 --ignore-case 'automation=true' <<< $tags || true)
    permanent=$(egrep --only-matching --max-count=1 \
                --ignore-case 'permanent=true' <<< $tags || true)

    if [[ -n "$permanent" ]]; then
        msg "Retaining forever $name | $tags"
        # Permanent AMIs should never ever have a deprecation date set
        $AWS ec2 disable-image-deprecation --image-id "$ami_id" > /dev/null
        continue
    fi

    # Any image matching the currently in-use IMG_SFX or IMPORT_IMG_SFX
    # must always be preserved.  Values are defined in cirrus.yml
    # shellcheck disable=SC2154
    if [[ "$name" =~ $IMG_SFX ]] || [[ "$name" =~ $IMPORT_IMG_SFX ]]; then
        msg "Retaining current (latest) image $name | $tags"
        continue
    fi

    # For IAM (security) policy, an "automation" tag is always required
    if [[ -z "$automation" ]]
    then
        reason="Missing 'automation' metadata; Tags: $tags"
        echo "EC2 $ami_id $reason" >> $TOOBSOLETE
        continue
    fi

    unset lltvalue last_used_timestamp last_used_ymd
    if lltvalue=$("${lltcmd[@]}" $ami_id | jq -r -e ".Value") && [[ -n "$lltvalue" ]]; then
        last_used_timestamp=$(date --date="$lltvalue" +%s)
        last_used_ymd=$(date --date="@$last_used_timestamp" --iso-8601=date)
        tags+=",lastLaunchedTime=$last_used_ymd"
    else
        reason="Missing 'lastLaunchedTime' metadata; Tags: $tags"
        echo "EC2 $ami_id $reason" >> $TOOBSOLETE
        continue
    fi

    if [[ "$last_used_timestamp" -le $THRESHOLD ]]; then
        reason="Used over $TOO_OLD_DESC on $last_used_ymd; Tags: $tags"
        echo "EC2 $ami_id $reason" >> $TOOBSOLETE
        continue
    else
        msg "Retaining $ami_id | $created_ymd | $state | $tags"
        if [[ "$dep" != "null" ]]; then
            msg "    Removing previously set AMI deprecation timestamp: $dep"
            # Ignore confirmation output.
            $AWS ec2 disable-image-deprecation --image-id "$ami_id" > /dev/null
        fi
    fi
done

COUNT=$(<"$IMGCOUNT")
msg "########################################################################"
msg "Obsoleting $OBSOLETE_LIMIT random images of $COUNT examined:"

# Require a minimum number of images to exist.  Also if there is some
# horrible scripting accident, this limits the blast-radius.
if [[ "$COUNT" -lt $OBSOLETE_LIMIT ]]
then
    die 0 "Safety-net Insufficient images ($COUNT) to process ($OBSOLETE_LIMIT required)"
fi

# Don't let one bad apple ruin the whole bunch
ERRORS=0
sort --random-sort $TOOBSOLETE | tail -$OBSOLETE_LIMIT | \
    while read -r cloud image_name reason; do

    msg "Obsoleting $cloud image $image_name:${NOR} $reason"
    if ((DRY_RUN)); then
        msg "    Dry-run: No changes made"
    elif [[ "$cloud" == "GCP" ]]; then
        # Ref: https://cloud.google.com/compute/docs/images/create-delete-deprecate-private-images#deprecating_an_image
        # Note: --delete-in creates deprecated.delete(from imgobsolete container)
        # The imgprune container is required to actually delete the image.
        $GCLOUD compute images deprecate $image_name \
                --state=OBSOLETE --delete-in="${TOO_OLD_DAYS}d" \
            || ERRORS=$((ERRORS+1))
    elif [[ "$cloud" == "EC2" ]]; then
        # Note: Image will be automatically deleted in 30 days unless manual
        # intervention performed. The imgprune container is NOT used for AWS
        # image pruning!
        if ! status=$($AWS ec2 enable-image-deprecation --image-id "$image_name" \
                      --deprecate-at $(date --utc --date "+$TOO_OLD_DAYS days" \
                      --iso-8601=date)); then
            ERRORS=$((ERRORS+1))
        elif [[ $(jq -r -e ".Return"<<<"$status") != "true" ]]; then
            ERRORS=$((ERRORS+1))
        fi
    else
        die 1 "Unknown/Unsupported cloud '$cloud' record encountered in \$TOOBSOLETE file"
    fi
done

if ((ERRORS)); then
    die 1 "Updating $ERRORS images failed (see above)."
fi
