#!/usr/bin/env bash

set -e

# shellcheck source=./lib_entrypoint.sh
source /usr/local/bin/lib_entrypoint.sh

req_env_var GCPJSON GCPNAME GCPPROJECT IMGNAMES BUILDID REPOREF

gcloud_init

# These must be defined by the cirrus-ci job using the container
# shellcheck disable=SC2154
ARGS="
    --update-labels=last-used=$(date +%s)
    --update-labels=build-id=$BUILDID
    --update-labels=repo-ref=$REPOREF
    --update-labels=project=$GCPPROJECT
"

# Must be defined by the cirrus-ci job using the container
# shellcheck disable=SC2154
for image in $IMGNAMES
do
    $GCLOUD compute images update "$image" $ARGS &
done

wait || echo "Warning: No \$IMGNAMES were specified."
