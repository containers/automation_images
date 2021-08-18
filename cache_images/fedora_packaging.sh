#!/bin/bash

# This script is called from fedora_setup.sh and various Dockerfiles.
# It's not intended to be used outside of those contexts.  It assumes the lib.sh
# library has already been sourced, and that all "ground-up" package-related activity
# needs to be done, including repository setup and initial update.

set -e

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# packer and/or a --build-arg define this envar value uniformly
# for both VM and container image build workflows.
req_env_vars PACKER_BUILD_NAME

# Do not enable updates-testing on the 'prior' Fedora release images
# as a matter of general policy.  Historically there have been many
# problems with non-uniform behavior when both supported Fedora releases
# receive container-related dependency updates at the same time.  Since
# the 'prior' release has the shortest support lifetime, keep it's behavior
# stable by only using released updates.
# shellcheck disable=SC2154
if [[ ! "$PACKER_BUILD_NAME" =~ prior ]]; then
    warn "Enabling updates-testing repository for $PACKER_BUILD_NAME"
    lilto ooe.sh $SUDO dnf install -y 'dnf-command(config-manager)'
    lilto ooe.sh $SUDO dnf config-manager --set-enabled updates-testing
else
    warn "NOT enabling updates-testing repository for $PACKER_BUILD_NAME"
fi

msg "Updating/Installing repos and packages for $OS_REL_VER"

bigto ooe.sh $SUDO dnf update -y

INSTALL_PACKAGES=(\
    autoconf
    automake
    bash-completion
    bridge-utils
    btrfs-progs-devel
    buildah
    bzip2
    conmon
    containernetworking-plugins
    containers-common
    criu
    crun
    curl
    device-mapper-devel
    docker-compose
    dnsmasq
    e2fsprogs-devel
    emacs-nox
    file
    findutils
    fuse3
    fuse3-devel
    gcc
    git
    glib2-devel
    glibc-devel
    glibc-static
    gnupg
    go-md2man
    golang
    gpgme
    gpgme-devel
    grubby
    hostname
    httpd-tools
    iproute
    iptables
    jq
    krb5-workstation
    libassuan
    libassuan-devel
    libblkid-devel
    libcap-devel
    libffi-devel
    libgpg-error-devel
    libmsi1
    libnet
    libnet-devel
    libnl3-devel
    libseccomp
    libseccomp-devel
    libselinux-devel
    libtool
    libxml2-devel
    libxslt-devel
    lsof
    make
    mlocate
    msitools
    nfs-utils
    nmap-ncat
    openssl
    openssl-devel
    ostree-devel
    pandoc
    parallel
    pkgconfig
    podman
    procps-ng
    protobuf
    protobuf-c
    protobuf-c-devel
    protobuf-devel
    python-pip-wheel
    python-setuptools-wheel
    python-wheel-wheel
    python2
    python3-PyYAML
    python3-coverage
    python3-dateutil
    python3-docker
    python3-fixtures
    python3-libselinux
    python3-libsemanage
    python3-libvirt
    python3-pip
    python3-psutil
    python3-pylint
    python3-pyxdg
    python3-requests
    python3-requests-mock
    redhat-rpm-config
    rpcbind
    rsync
    runc
    sed
    skopeo
    slirp4netns
    socat
    tar
    time
    unzip
    vim
    wget
    which
    xz
    zip
    zlib-devel
    zstd
)

# Perl module packaging changes between F32 and F33
case "$OS_RELEASE_VER" in
    32) INSTALL_PACKAGES+=( python3-pytoml ) ;;
    33) ;&
    34) INSTALL_PACKAGES+=( perl-FindBin python-toml ) ;;
    *) die "Unknown/Unsupported \$OS_REL_VER '$OS_REL_VER'" ;;
esac

# When installing during a container-build, having this present
# will seriously screw up future dnf operations in very non-obvious ways.
if ! ((CONTAINER)); then
    INSTALL_PACKAGES+=( \
        container-selinux
        libguestfs-tools
        selinux-policy-devel
        policycoreutils
    )
else
    EXARG="--exclude=selinux*"
fi


# Download these package files, but don't install them; Any tests
# wishing to, may install them using their native tools at runtime.
DOWNLOAD_PACKAGES=(\
    "cri-o-$(get_kubernetes_version)*"
    cri-tools
    "kubernetes-$(get_kubernetes_version)*"
    oci-umount
    parallel
    podman-docker
)

echo "Installing general build/test dependencies"
bigto $SUDO dnf install -y $EXARG "${INSTALL_PACKAGES[@]}"

# TODO: Temporarily side-load an updated buildah
# https://bodhi.fedoraproject.org/updates/FEDORA-2021-2bcbfc2b3c
# Remove this after the package (or later version) is available in repo.
if [[ "$OS_RELEASE_VER" =~ 33 ]]; then
    lilto $SUDO dnf update -y "https://kojipkgs.fedoraproject.org//packages/buildah/1.22.0/1.fc33/x86_64/buildah-1.22.0-1.fc33.x86_64.rpm"
fi

if [[ ${#DOWNLOAD_PACKAGES[@]} -gt 0 ]]; then
    echo "Downloading packages for optional installation at runtime, as needed."
    # Required for cri-o
    ooe.sh $SUDO dnf -y module enable cri-o:$(get_kubernetes_version)
    $SUDO mkdir -p "$PACKAGE_DOWNLOAD_DIR"
    cd "$PACKAGE_DOWNLOAD_DIR"
    lilto ooe.sh $SUDO dnf install -y 'dnf-command(download)'
    lilto $SUDO dnf download -y --resolve "${DOWNLOAD_PACKAGES[@]}"
fi

# It was observed in F33, dnf install doesn't always get you the latest/greatest
lilto $SUDO dnf update -y

echo "Configuring Go environment"
export GOPATH=/var/tmp/go
mkdir -p "$GOPATH"
eval $(go env | tee /dev/stderr)
export PATH="$GOPATH/bin:$PATH"
# shellcheck source=./podman_tooling.sh
source $SCRIPT_DIRPATH/podman_tooling.sh
