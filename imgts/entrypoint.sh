#!/usr/bin/env bash

# This script is set as, and intended to run as the `imgts` container's
# entrypoint. It's purpose is to operate on a list of VM Images, adding
# metadata to each.  It must be executed alongside any repository's
# automation, which produces or uses GCP VM Images.

set -e

# shellcheck source=./lib_entrypoint.sh
source /usr/local/bin/lib_entrypoint.sh

req_env_var GCPJSON GCPNAME GCPPROJECT IMGNAMES BUILDID REPOREF

gcloud_init

# Set this to 1 for testing
DRY_RUN="${DRY_RUN:-0}"

# These must be defined by the cirrus-ci job using the container
# shellcheck disable=SC2154
ARGS=(\
    "--update-labels=last-used=$(date +%s)"
    "--update-labels=build-id=$BUILDID"
    "--update-labels=repo-ref=$REPOREF"
    "--update-labels=project=$GCPPROJECT"
)

# Must be defined by the cirrus-ci job using the container
# shellcheck disable=SC2154
[[ -n "$IMGNAMES" ]] || \
    die 1 "No \$IMGNAMES were specified."

# Under some runtime conditions, not all images may be available
REQUIRE_ALL=${REQUIRE_ALL:-1}

# Don't allow one bad apple to ruin the whole batch
ERRIMGS=''

# It's possible for multiple simultaneous label updates to clash
CLASHMSG='Labels fingerprint either invalid or resource labels have changed'

# This function accepts a single argument: A Cirrus-CI build ID. The
# function looks up the build from Cirrus-CI to determine if it occured
# on a non-main branch.  If so the function returns zero.  Otherwise, it
# returns 1 for executions on behalf of the `main` branch, all PRs and
# all tags.  It will fully exit non-zero in case of any error.
is_release_branch_image(){
    local buildId api query result prefix branch tag
    buildId=$1
    api="https://api.cirrus-ci.com/graphql"
    query="{
        \"query\": \"query {
            build(id: $buildId) {
                branch
                tag
                pullRequest
            }
          }\"
        }"

    # This is mandatory, must never be unset, empty, or shorter than an actual ID.
    # Normally about 16-characters long.
    if ((${#buildId}<14)); then
        die 1 "Empty/invalid  BuildId '$buildId' passed to is_release_branch_image()"
    fi

    prefix=".data.build"
    result=$(curl --silent --location \
             --request POST --data @- --url "$api" <<<"$query") \
             || \
             die 2 "Error communicating with GraphQL API $api: $result"

    # Any problems with the GraphQL reply or mismatch of the JSON
    # structure (specified in query) is an error that operators should
    # be made aware of.
    if ! jq -e "$prefix" <<<"$result" &> /dev/null; then
        die 3 "Response from Cirrus API query '$query' has unexpected/invalid JSON structure:
$result"
    fi

    # Cirrus-CI always sets some branch value for all execution contexts
    if ! branch=$(jq -e --raw-output "${prefix}.branch" <<<"$result"); then
        die 4 "Empty/null branch value returned for build '$buildId':
$result"
    fi

    # This value will be empty/null for PRs and branch builds
    tag=$(jq --raw-output "${prefix}.tag" <<<"$result" | sed 's/null//g')

    # Cirrus-CI sets `branch=pull/#` for pull-requests, dependabot creates
    if [[ -z "$tag" && "$branch" =~ ^(v|release-)[0-9]+.* ]]; then
        msg "Found build $buildId for release branch '$branch'."
        return 0
    fi

    msg "Found build '$buildId' for non-release branch '$branch' and/or tag '$tag' (may be empty)."
    return 1
}

unset SET_PERM
if is_release_branch_image $BUILDID; then
    ARGS+=("--update-labels=permanent=true")
    SET_PERM=1
fi

if ((DRY_RUN)); then GCLOUD='echo'; fi

# Must be defined by the cirrus-ci job using the container
# shellcheck disable=SC2154
for image in $IMGNAMES
do
    if ! OUTPUT=$($GCLOUD compute images update "$image" "${ARGS[@]}" 2>&1); then
        echo "$OUTPUT" > /dev/stderr
        if grep -iq "$CLASHMSG" <<<"$OUTPUT"; then
            # Updating the 'last-used' label is most important.
            # Assume clashing update did this for us.
            msg "Warning: Detected simultaneous label update, ignoring clash."
            continue
        fi
        msg "Detected update error for '$image'" > /dev/stderr
        ERRIMGS="$ERRIMGS $image"
    else
        # Display the URI to the updated image for reference
        if ((SET_PERM)); then
            msg "IMAGE $image MARKED FOR PERMANENT RETENTION"
        else
            echo "Updated image $image last-used timestamp"
        fi
    fi
done

if [[ -n "$ERRIMGS" ]]; then
    die_or_warn=die
    ((REQUIRE_ALL)) || die_or_warn=warn
    $die_or_warn 2 "Failed to update one or more image timestamps: $ERRIMGS"
fi
