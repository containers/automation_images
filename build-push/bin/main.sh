#!/bin/bash

# This script is not intended for humans.  It should be run by automation
# at the branch-level in automation for the skopeo, buildah, and podman
# repositories.  It's purpose is to produce a multi-arch container image
# based on the contents of context subdirectory.  At runtime, $PWD is assumed
# to be the root of the cloned git repository.
#
# The first argument to the script, should be the URL of the git repository
# in question.  Though at this time, this is only used for labeling the
# resulting image.
#
# The second argument to this script is the relative path to the build context
# subdirectory.  The basename of this subdirectory may indicates the
# image flavor (i.e. `upstream`, `testing`, or `stable`). Depending
# on this value, the image may be pushed to multiple container registries
# under slightly different rules (see the next option).
#
# If the basename of the context directory (second argument) does NOT reflect
# the image flavor, this name may be passed in as a third argument.  Handling
# of this argument may be repository-specific, so check the actual code below
# to understand it's behavior.

set -eo pipefail

if [[ -r "/etc/automation_environment" ]]; then
    source /etc/automation_environment  # defines AUTOMATION_LIB_PATH
    #shellcheck disable=SC1090,SC2154
    source "$AUTOMATION_LIB_PATH/common_lib.sh"
    #shellcheck source=../lib/autoupdate.sh
    source "$AUTOMATION_LIB_PATH/autoupdate.sh"
else
    echo "Expecting to find automation common library installed."
    exit 1
fi

# Careful: Changing the error message below could break auto-update test.
if [[ "$#" -lt 2 ]]; then
    #shellcheck disable=SC2145
    die "Must be called with at least two arguments, got '$@'"
fi

if [[ -z $(type -P build-push.sh) ]]; then
    die "It does not appear that build-push.sh is installed properly"
fi

if ! [[ -d "$PWD/.git" ]]; then
    die "The current directory ($PWD) does not appear to be the root of a git repo."
fi

# Assume transitive debugging state for build-push.sh if set
if [[ "$(automation_version | cut -d '.' -f 1)" -ge 4 ]]; then
    # Valid for version 4.0.0 and above only
    export A_DEBUG
else
    export DEBUG
fi

# Arches to build by default - may be overridden for testing
ARCHES="${ARCHES:-amd64,ppc64le,s390x,arm64}"

# First arg (REPO_URL) is the clone URL for repository for informational purposes
REPO_URL="$1"
REPO_NAME=$(basename "${REPO_URL%.git}")
# Second arg (CTX_SUB) is the context subdirectory relative to the clone path
CTX_SUB="$2"
# Historically, the basename of second arg set the image flavor(i.e. `upstream`,
# `testing`, or `stable`).  For cases where this convention doesn't fit,
# it's possible to pass the flavor-name as the third argument.  Both methods
# will populate a "FLAVOR" build-arg value.
if [[ "$#" -lt 3 ]]; then
    FLAVOR_NAME=$(basename "$CTX_SUB")
elif [[ "$#" -ge 3 ]]; then
    FLAVOR_NAME="$3"  # An empty-value is valid
else
    die "Expecting a non-empty third argument indicating the FLAVOR build-arg value."
fi
_REG="quay.io"
if [[ "$REPO_NAME" =~ testing ]]; then
    _REG="example.com"
fi
# Allow detection of non-default REPO_FQIN
DEFAULT_REPO_FQIN="$_REG/$REPO_NAME/$FLAVOR_NAME"
REPO_FQIN="${REPO_FQIN:-$DEFAULT_REPO_FQIN}"
req_env_vars REPO_URL REPO_NAME CTX_SUB FLAVOR_NAME

# Common library defines SCRIPT_FILENAME
# shellcheck disable=SC2154
dbg "$SCRIPT_FILENAME operating constants:
    ARCHES=$ARCHES
    REPO_URL=$REPO_URL
    REPO_NAME=$REPO_NAME
    CTX_SUB=$CTX_SUB
    FLAVOR_NAME=$FLAVOR_NAME
    REPO_FQIN=$REPO_FQIN
"

# Set non-zero to avoid actually executing build-push, simply print
# the command-line that would have been executed
DRYRUN=${DRYRUN:-0}
_DRNOPUSH=""
if ((DRYRUN)); then
    _DRNOPUSH="--nopush"
    warn "Operating in dry-run mode with $_DRNOPUSH"
fi

### MAIN

declare -a build_args
if [[ -n "$FLAVOR_NAME" ]]; then
    build_args=(--build-arg "FLAVOR=$FLAVOR_NAME")
fi

head_sha=$(git rev-parse HEAD)
dbg "HEAD is $head_sha"
# Labels to add to all images
# N/B: These won't show up in the manifest-list itself, only it's constituents.
lblargs="\
    --label=org.opencontainers.image.source=$REPO_URL \
    --label=org.opencontainers.image.revision=$head_sha \
    --label=org.opencontainers.image.created=$(date -u --iso-8601=seconds)"
dbg "lblargs=$lblargs"

modcmdarg="tag_version.sh $FLAVOR_NAME"

# For stable images, the version number of the command is needed for tagging.
if [[ "$FLAVOR_NAME" == "stable" ]]; then
    # only native arch is needed to extract the version
    dbg "Building local-arch image to extract stable version number"
    podman build -t $REPO_FQIN "${build_args[@]}" ./$CTX_SUB

    case "$REPO_NAME" in
        skopeo) version_cmd="--version" ;;
        buildah) version_cmd="buildah --version" ;;
        podman)
            version_cmd="podman --version"
            if [[ "$REPO_FQIN" =~ pipglr ]]; then
                version_cmd="--version"
            fi
            ;;
        testing) version_cmd="cat FAKE_VERSION" ;;
        *) die "Unknown/unsupported repo '$REPO_NAME'" ;;
    esac

    pvcmd="podman run -i --rm $REPO_FQIN $version_cmd"
    dbg "Extracting version with command: $pvcmd"
    version_output=$($pvcmd)
    dbg "version output:
    $version_output
    "

    # `gitlab-runner --version` outputs a table of version numbers. to parse.
    if [[ "$REPO_FQIN" =~ pipglr ]]; then
        img_cmd_version=$(egrep '^Version:' <<<"$version_output" | tr -d '[:space:]' | cut -d: -f2)
    else
        img_cmd_version=$(awk -r -e '/^.+ version /{print $3}' <<<"$version_output")
    fi
    dbg "parsed version: $img_cmd_version"
    test -n "$img_cmd_version"
    lblargs="$lblargs --label=org.opencontainers.image.version=$img_cmd_version"
    # Prevent temporary build colliding with multi-arch manifest list (built next)
    # but preserve image (by ID) for use as cache.
    dbg "Un-tagging $REPO_FQIN"
    podman untag $REPO_FQIN

    # tag-version.sh expects this arg. when FLAVOR_NAME=stable
    modcmdarg+=" $img_cmd_version"

    # Stable images get pushed to 'containers' namespace as latest & version-tagged,
    # unless they're using an overriden $REPO_FQIN value.  In the later case,
    # assume the author knows what they're doing.
    [[ "$REPO_FQIN" != "$DEFAULT_REPO_FQIN" ]] || \
    build-push.sh \
        $_DRNOPUSH \
        --arches=$ARCHES \
        --modcmd="$modcmdarg" \
        $_REG/containers/$REPO_NAME \
        ./$CTX_SUB \
        $lblargs \
        "${build_args[@]}"
fi

# All images are pushed to quay.io/<reponame>, both
# latest and version-tagged (if available).
build-push.sh \
    $_DRNOPUSH \
    --arches=$ARCHES \
    --modcmd="$modcmdarg" \
    $REPO_FQIN \
    ./$CTX_SUB \
    $lblargs \
    "${build_args[@]}"
