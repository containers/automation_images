#!/bin/bash

# This script allows stuffing a dnf cache directory with both
# metadata and packages, for a list of architectures.  It assumes
# the same Fedora release version as the executing platform unless
# $RELEASE is overriden. It requires the containers/automation
# common libraries are installed and the following env. vars. are
# non-empty:
#
# CACHEDIR - Directory path under which both metadata & packages will
#            be stored (under platform specific subdirectory tree).
# ARCHES - Whitespace separated list of architecture names
# PACKAGES - Whitespace separated list of packages to seed in cache

set -ea
[[ -n "$AUTOMATION_LIB_PATH" ]] || source /etc/automation_environment
source $AUTOMATION_LIB_PATH/common_lib.sh
set +a

req_env_vars ARCHES PACKAGES CACHEDIR OS_RELEASE_VER SCRIPT_FILENAME DEBUG

declare -a _ARCHES
# We want to do word-splitting
# shellcheck disable=SC2206
_ARCHES=( $ARCHES )
declare -a _PACKAGES
# shellcheck disable=SC2206
_PACKAGES=( $PACKAGES )

RELEASE="${RELEASE:-$OS_RELEASE_VER}"

# First arg must be name of architecture
# Second arg must be either 'makecache' or 'download'
dnfarch(){
    local arch
    arch="$1"
    shift
    local cmd
    cmd=$1
    [[ -n "$arch" ]] || die "Missing arch arument to dnfarch()"

    # Don't download into $PWD
    local ddarg
    if [[ "$cmd" == "download" ]]; then
        # Already checked by req_env_vars()
        # shellcheck disable=SC2154
        ddarg="--downloaddir=$CACHEDIR"
    fi

    local mq="-q"
    local _showrun
    # Vars. already checked by req_env_vars()
    # shellcheck disable=SC2154
    if ((DEBUG)); then
        _showrun="showrun"
        mq=""
    fi
    # Have to put --cachedir option path under here too, otherwise
    # metadata gets downloaded every run.
    $_showrun dnf --setopt=ignorearch=true --releasever="$RELEASE" \
        --setopt=keepcache=true --setopt=cachedir="$CACHEDIR" \
        $mq -y --setopt=arch=$arch $ddarg "$@"
}

wait_jobs() {
    local job
    dbg "Waiting for background jobs to complete."
    for job in "$@"; do
        dbg "Waiting on job '$job'"
        # This isn't perfect, it will miss special-case exit 127 but
        # this should be unlikely given the usage of this function.
        if ! wait -n $job; then
            dbg "Background job $job non-zero exit status"
            # This could be hard to debug, but being more verbose
            # about the failing command would unacceptably increasse
            # the scripts complexity.  Rely on dnf's error messages
            # being useful.
            die "At least one operation failed, bailing out."
        fi
        dbg "Job '$job' complete"
    done
    jobs=()
}

for_each_arch() {
    local cmd
    local arch
    local -a jobs
    for arch in "${_ARCHES[@]}"; do
        # For display, command needs both whitespace and special quote handling.
        cmd=$(printf "%q " "dnfarch" "$arch" "$@")
        $cmd &
        jobs+=($!)
        dbg "New job $!: $cmd"
    done
    wait_jobs "${jobs[@]}"
}

mkdir -p "$CACHEDIR"

msg "Downloading Fedora $RELEASE metadata in parallel"
for_each_arch makecache

msg "Downloading Fedora $RELEASE packages in parallel"
for_each_arch download "${_PACKAGES[@]}"
