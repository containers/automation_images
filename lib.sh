

# This file is intended to be sourced by other scripts running on
# aa Fedora or Debian VM during various stages of initial setup.
# Using it in any other way or context unlikely to do anything
# useful for you.

# By default, assume we're not running inside a container
CONTAINER="${CONTAINER:-0}"

OS_RELEASE_VER="$(source /etc/os-release; echo $VERSION_ID | tr -d '.')"
OS_RELEASE_ID="$(source /etc/os-release; echo $ID)"
OS_REL_VER="$OS_RELEASE_ID-$OS_RELEASE_VER"

# Avoid getting stuck waiting for user input
[[ "$OS_RELEASE_ID" != "debian" ]] || \
    export DEBIAN_FRONTEND="noninteractive"

# This location is checked by automation in other repos, please do not change.
PACKAGE_DOWNLOAD_DIR=/var/cache/download

# N/B: This is managed by renovate
INSTALL_AUTOMATION_VERSION="5.0.0"

# Mask secrets in show_env_vars() from automation library
SECRET_ENV_RE='(^PATH$)|(^BASH_FUNC)|(^_.*)|(.*PASSWORD.*)|(.*TOKEN.*)|(.*SECRET.*)|(.*ACCOUNT.*)|(.+_JSON)|(AWS.+)|(.*SSH.*)|(.*GCP.*)'

if [[ -r "/etc/automation_environment" ]]; then
    source /etc/automation_environment
    #shellcheck disable=SC1090,SC2154
    source $AUTOMATION_LIB_PATH/common_lib.sh

    # Shortcuts to common retry/timeout calls
    lilto() { err_retry 8 1000 "" "$@"; }  # just over 4 minutes max
    bigto() { err_retry 7 5670 "" "$@"; }  # 12 minutes max
else  # Automation common library not installed yet
    echo "Warning: Automation library not found. Assuming it's not yet installed"
    die() { echo "ERROR: ${1:-No error message provided}"; exit 1; }
    lilto() { die "Automation library not installed; Required for lilto()"; }
    bigto() { die "Automation library not installed; Required for bigto()"; }
fi

# Setting noninteractive is critical, apt-get can hang w/o it.
# N/B: Must be done _after_ potential loading of automation libraries
export SUDO="env DEBIAN_FRONTEND=noninteractive"
if [[ "$UID" -ne 0 ]]; then
    export SUDO="sudo env DEBIAN_FRONTEND=noninteractive"
fi

install_automation_tooling() {
    local version_arg
    version_arg="$INSTALL_AUTOMATION_VERSION"

    if [[ "$1" == "latest" ]]; then
      version_arg="latest"
      shift
    fi

    # This script supports installing all current and previous versions
    local installer_url="https://raw.githubusercontent.com/containers/automation/master/bin/install_automation.sh"
    curl --silent --show-error --location \
         --url "$installer_url" | \
         $SUDO env INSTALL_PREFIX=/usr/share /bin/bash -s - \
        "$version_arg" "$@"
    # This defines AUTOMATION_LIB_PATH
    source /usr/share/automation/environment
    #shellcheck disable=SC1090
    source $AUTOMATION_LIB_PATH/common_lib.sh
}

custom_cloud_init() {
    #shellcheck disable=SC2154
    CUSTOM_CLOUD_CONFIG_DEFAULTS="$REPO_DIRPATH/base_images/cloud-init/$OS_RELEASE_ID/cloud.cfg.d"
    if [[ -d "$CUSTOM_CLOUD_CONFIG_DEFAULTS" ]]
    then
        echo "Installing custom cloud-init defaults"
        mkdir -p /etc/cloud/cloud.cfg.d  # Should exist, sometimes doesn't.
        $SUDO cp -v --dereference \
            "$CUSTOM_CLOUD_CONFIG_DEFAULTS"/* \
            /etc/cloud/cloud.cfg.d/
    else
        echo "Could not find any files in $CUSTOM_CLOUD_CONFIG_DEFAULTS"
        exit 1
    fi
}

clear_cred_files() {
    set +ex
    if ((${#GAC_FILEPATH}>0)); then
        rm -f "$GAC_FILEPATH"
    fi
    if ((${#AWS_SHARED_CREDENTIALS_FILE}>0)); then
        rm -f "$AWS_SHARED_CREDENTIALS_FILE"
    fi
}

# This function may only/ever be used within Cirrus-CI
set_gac_filepath() {
    # shellcheck disable=SC2154
    if [[ -z "$CI" ]] || [[ "$CI" != "true" ]] || [[ "$CIRRUS_CI" != "$CI" ]]; then
        die "Unexpected \$CI=$CI and/or \$CIRRUS_CI=$CIRRUS_CI"
    elif ((${#GAC_JSON}<=2)); then
        die "Required (secret) \$GAC_JSON value appears to be empty"
    elif grep -iq "ENCRYPTED" <<<"$GAC_JSON"; then
        die "Decrpytion of \$GAC_JSON failed."
    fi
    set +x;
    GAC_FILEPATH=$(mktemp -p '' '.XXXXXXXX.')
    export GAC_FILEPATH
    trap clear_cred_files EXIT
    echo "$GAC_JSON" > "$GAC_FILEPATH"
    unset GAC_JSON;
}

# This function may only/ever be used within Cirrus-CI
set_aws_filepath() {
    # shellcheck disable=SC2154
    if [[ -z "$CI" ]] || [[ "$CI" != "true" ]] || [[ "$CIRRUS_CI" != "$CI" ]]; then
        die "Unexpected \$CI=$CI and/or \$CIRRUS_CI=$CIRRUS_CI"
    elif ((${#AWS_INI}<=2)); then
        die "Required (secret) \$AWS_INI value appears to be empty"
    elif grep -iq "ENCRYPTED" <<<"$AWS_INI"; then
        die "Decrpytion of \$AWS_INI failed."
    fi
    set +x;
    # Magic filename packer is sensitive to
    AWS_SHARED_CREDENTIALS_FILE=$(mktemp -p '' '.XXXXXXXX.')
    export AWS_SHARED_CREDENTIALS_FILE
    trap clear_cred_files EXIT
    echo "$AWS_INI" > "$AWS_SHARED_CREDENTIALS_FILE"
    unset AWS_INI;
}

# Almost every CI-driven image build includes a `$PACKER_BUILDS`
# or `$TARTGET_NAME` specifier.  Leverage appearance of a `no_*`
# PR-label prefix to bypass certain builds when running under CI.
skip_on_pr_label() {
    req_env_vars AUTOMATION_LIB_PATH  # Automation library is required

    local build_spec pr_labels pr_label

    if [[ -z "$CI" ]] || [[ "$CI" != 'true' ]]; then
        warn "Skipping builds by PR-label only works under CI"
        return 1  # reverse-logic: DO NOT SKIP
    fi

    build_spec="${TARGET_NAME:-$PACKER_BUILDS}"
    pr_labels=$(get_pr_labels)  # Will fail if not running under CI
    if [[ -z "$build_spec" ]]; then
        warn "Both \$TARGET_NAME and \$PACKER_BUILDS found empty, continuing anyway."
        return 1
    elif [[ -z "$pr_labels" ]]; then
        warn "No labels found on PR, continuing with build."
        return 1
    fi

    # N/B: Labels can contain spaces, assume maintainers are smart enough
    #      to not do this, or they're not important for this usage.
    for pr_label in $pr_labels; do
        if [[ "$pr_label" =~ no_.+ ]] && [[ "${pr_label#no_}" == "$build_spec" ]]; then
            warn "Found '$pr_label' for '$build_spec', skipping build."
            return 0  # reverse-logic: DO skip.
        fi
        dbg "Label '$pr_label' no match to '$build_spec'."
    done
    return 1  # Do not skip
}

# print a space-separated list of labels when run under Cirrus-CI for a PR
get_pr_labels() {
    req_env_vars CIRRUS_CI CIRRUS_REPO_CLONE_TOKEN
    req_env_vars CIRRUS_REPO_OWNER CIRRUS_REPO_NAME

    # Empty for non-PRs
    # shellcheck disable=SC2154
    [[ -n "$CIRRUS_PR" ]] || return 0

    local query h_accept h_content api result fltrpfx
    local filter labels h_auth h_accept h_content

    # shellcheck disable=SC2154
    h_auth="Authorization: bearer $CIRRUS_REPO_CLONE_TOKEN"
    h_accept='Accept: application/vnd.github.antiope-preview+json'
    h_content='Content-Type: application/json'
    api="https://api.github.com/graphql"
    # shellcheck disable=SC2154
    query="{
        \"query\": \"query {
          repository(owner: \\\"$CIRRUS_REPO_OWNER\\\",
                     name: \\\"$CIRRUS_REPO_NAME\\\") {
            pullRequest(number: $CIRRUS_PR) {
              labels(first: 100) {
                nodes {
                  name
                }
              }
            }
          }
        }\"
    }"
    # Used to check that properly formated result was returned
    fltrpfx=".data.repository.pullRequest.labels"
    # Used to get the actual list of labels
    filter="${fltrpfx}.nodes[].name"

    dbg "Issuing '$query'"
    result=$(curl --silent --location \
             -H "$h_auth" -H "$h_accept" -H "$h_content" \
             --request POST --data @- --url "$api" <<<"$query") \
             || \
             die "Error communicating with GraphQL API $api: $result"
    # GraphQL sometimes returns errors inline, try to detect this.
    if ! jq -e "$fltrpfx" <<<"$result" &> /dev/null; then
        die "Received unexpected reply: $result"
    fi

    dbg "Filtering & formatting line-separated result: '$result'"
    labels=$(jq --raw-output "$filter" <<<"$result" | \
             tr '[:space:]' ' ' | sed -e 's/ $//')

    dbg "Outputting space-separated labels: '$labels'"
    echo -n "$labels"
}

remove_netavark_aardvark_files() {
    req_env_vars OS_RELEASE_ID
    # OS_RELEASE_ID is defined by automation-library
    # shellcheck disable=SC2154
    if [[ "$OS_RELEASE_ID" =~ "debian" ]]
    then
        die "Debian netavark/aardvark-dns testing is not supported"
    fi

        LISTING_CMD="rpm -ql podman"

    # yum/dnf/dpkg may list system directories, only remove files
    rpm -ql netavark aardvark-dns | while read fullpath
    do
        # Sub-directories may contain unrelated/valuable stuff
        if [[ -d "$fullpath" ]]; then continue; fi
        $SUDO rm -vf "$fullpath"
    done
}

# Warning: DO NOT USE the following functions willy-nilly!
# They are only intended to be called by other setup scripts, as the very
# last step during the build process.  They're purpose is to "reset" the
# VM so all the first-boot operations happen again normally (like
# generating new ssh host keys, resizing partitions, etc.)

# Ref: https://cloud.google.com/compute/docs/oslogin
# Google "OS-login" service manages persistent accounts automatically.
# The "packer" tool also does this during image creation, and the two
# have been observed causing conflicts upon reboot.  When finalizing
# an image for re-use, remove all standard user accounts AND home
# directories.
clean_automatic_users() {
    DELUSER="deluser --remove-home"
    DELGROUP="delgroup --only-if-empty"
    if [[ "$OS_RELEASE_ID" == "fedora" ]]; then
        DELUSER="userdel --remove";
        DELGROUP="groupdel"
    fi
    # Avoid needing to parse login.defs (fedora) and deluser.conf (Debian)
    # for the UID/GID ranges standard user accounts.
    cd /home || exit
    for account in *; do
        # Cannot remove active user executing sudo - assume this is "packer"
        # and will be removed by the tool upon image build completion.
        if id "$account" &> /dev/null && [[ "$account" != "$USER" ]]; then
            $SUDO $DELUSER "$account"
            $SUDO $DELGROUP "$account" || true
        fi
    done
    $SUDO rm -rf /home/*/.ssh/*
}

# Workaround for "NetworkManager doing weird things" (leading to testing-flakes)
# Ref:https://github.com/containers/podman/issues/11123#issuecomment-912516145
nm_ignore_cni() {
    echo "Deploying NetworkManager anti-weird-things workaround"
    $SUDO mkdir -p /etc/NetworkManager/conf.d/
    cat << EOF | $SUDO tee /etc/NetworkManager/conf.d/podman-cni.conf
[keyfile]
unmanaged-devices=interface-name:*podman*;interface-name:veth*
EOF
}

common_finalize() {
    set -x  # extra detail is no-longer necessary
    cd /
    clean_automatic_users
    $SUDO cloud-init clean --logs
    if ! ((CONTAINER)); then
        # Prevent periodically activated services interfering with testing
        /bin/bash $(dirname ${BASH_SOURCE[0]})/systemd_banish.sh
    fi
    $SUDO rm -rf /var/lib/cloud/instanc*
    $SUDO rm -rf /root/.ssh/*
    $SUDO rm -rf /etc/ssh/*key*
    $SUDO rm -rf /tmp/* /var/tmp/automation_images
    $SUDO rm -rf /tmp/.??*
    echo -n "" | $SUDO tee /etc/machine-id
    $SUDO sync
    if ! ((CONTAINER)); then
        # This helps when google goes to compress the image
        $SUDO fstrim -av
    fi
}

# Called during VM Image setup, not intended for general use.
rh_finalize() {
    set +e  # Don't fail at the very end
    if ((CONTAINER)); then  # try to save a little space
        msg "Cleaning up packaging metadata and cache"
        $SUDO dnf clean all
        $SUDO rm -rf /var/cache/dnf
    fi
    set -x
    # Packaging cache is preserved across builds of container images
    $SUDO rm -f /etc/udev/rules.d/*-persistent-*.rules
    $SUDO touch /.unconfigured  # force firstboot to run

    echo
    echo "# PACKAGE LIST"
    rpm -qa | sort
}

# Called during VM Image setup, not intended for general use.
debian_finalize() {
    set +e  # Don't fail at the very end
    # N/B: Several CI setups depend on VMs with downloaded/cached
    # packages under /var/cache/download a.k.a. /var/cache/apt/archives.
    # Avoid apt cache cleaning on Debian VMs!
    if ((CONTAINER)); then  # try to save a little space for containers
        msg "Cleaning up packaging metadata and cache"
        $SUDO apt-get clean
        $SUDO rm -rf /var/cache/apt
    fi
    set -x
    # Packaging cache is preserved across builds of container images
    # pipe-cat is not a NOP! It prevents using $PAGER and then hanging
    echo "# PACKAGE LIST"
    dpkg -l | cat
}

finalize() {
    if [[ "$OS_RELEASE_ID" == "centos" ]]; then
        rh_finalize
    elif [[ "$OS_RELEASE_ID" == "fedora" ]]; then
        rh_finalize
    elif [[ "$OS_RELEASE_ID" == "debian" ]]; then
        debian_finalize
    else
        die "Unknown/Unsupported Distro '$OS_RELEASE_ID'"
    fi

    common_finalize
}
