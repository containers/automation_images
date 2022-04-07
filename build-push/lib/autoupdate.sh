

# This script is not intended for humans.  It should only be sourced by
# main.sh.  If BUILDPUSHAUTOUPDATED!=0 this it will be a no-op.  Otherwise,
# it will download the latest version of the build-push scripts and re-exec
# main.sh.  This allows the scripts to be updated without requiring new VM
# images to be composed and deployed.
#
# WARNING: Changes to this script _do_ require new VM images as auto-updating
# the auto-update script would be complex and hard to test.

# Must be exported - .install.sh checks this is set.
export BUILDPUSHAUTOUPDATED="${BUILDPUSHAUTOUPDATED:-0}"

if ! ((BUILDPUSHAUTOUPDATED)); then
    msg "Auto-updating build-push operational scripts..."
    #shellcheck disable=SC2154
    GITTMP=$(mktemp -p '' -d "$MKTEMP_FORMAT")
    trap "rm -rf $GITTMP" EXIT

    msg "Obtaining latest version..."
    git clone --quiet --depth=1 \
        https://github.com/containers/automation_images.git \
        "$GITTMP"
    msg "Installing..."
    cd $GITTMP/build-push || exit 1
    bash ./.install.sh
    # Important: Return to directory main.sh was started from
    cd - || exit 1
    rm -rf "$GITTMP"

    #shellcheck disable=SC2145
    msg "Re-executing main.sh $@..."
    export BUILDPUSHAUTOUPDATED=1
    exec main.sh "$@"  # guaranteed on $PATH
fi
