#!/usr/bin/env bash

# This script is set as, and intended to run as the `orphanvms` container's
# entrypoint.  It searches for actibe VM instances with an "old" `creation`
# timestamp.

set -eo pipefail

# shellcheck source=imgts/lib_entrypoint.sh
source /usr/local/bin/lib_entrypoint.sh

req_env_var GCPJSON GCPNAME GCPPROJECTS

# Try not to make any output when no orphan VMs are found
GCLOUD="$GCLOUD --quiet --verbosity=error"
EVERYTHING=${EVERYTHING:-0}  # set to '1' for testing
TOO_OLD='3 days ago'
NOW=$(date +%s)
THRESHOLD=$(date --date="$TOO_OLD" +%s)
# Format Ref: https://cloud.google.com/sdk/gcloud/reference/topic/formats
FORMAT='value[quote](name,creationTimestamp,labels)'
# Filter Ref: https://cloud.google.com/sdk/gcloud/reference/topic/filters
FILTER="status!=TERMINATED AND creationTimestamp<$(date --date="$TOO_OLD" --iso-8601=date)"
if ((EVERYTHING)); then
    FILTER="status:*"
fi

# shellcheck disable=SC2154,SC2153
for GCPPROJECT in $GCPPROJECTS; do
    OUTPUT=$(mktemp -p '' orphanvms_${GCPPROJECT}_XXXXX)
    # --quiet mode doesn't prevent printing activation message.
    gcloud_init |& grep -Eiv '^Activated service account credentials for:' || true

    echo "Orphaned $GCPPROJECT VMs:" > $OUTPUT
    # Ref: https://cloud.google.com/compute/docs/images/create-delete-deprecate-private-images#deprecating_an_image
    $GCLOUD compute instances list --format="$FORMAT" --filter="$FILTER" | \
        while read name creationTimestamp labels
        do
            if [[ -z "$name" ]] || [[ -z "$creationTimestamp" ]]; then continue; fi
            created_epoch=$(date --date=$creationTimestamp +%s)
            age_days=$((($NOW - $created_epoch) / (60 * 60 * 24)))
            # running in a child-process, must buffer into file.
            echo -e "* VM $name is $age_days days old and labeled '$labels'" >> $OUTPUT
        done

    if [[ $(wc -l $OUTPUT | awk '{print $1}') -gt 1 ]]; then
        cat $OUTPUT
    fi
done
