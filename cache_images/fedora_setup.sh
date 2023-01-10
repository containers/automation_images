#!/bin/bash

# This script is called by packer on the subject fedora VM, to setup the podman
# build/test environment.  It's not intended to be used outside of this context.

set -e

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")
SCRIPT_DIRPATH=$(dirname "$SCRIPT_FILEPATH")
REPO_DIRPATH=$(realpath "$SCRIPT_DIRPATH/../")

if ! ((CONTAINER)); then
    # Run as quickly as possible after boot
    /bin/bash $REPO_DIRPATH/systemd_banish.sh
fi

# shellcheck source=./lib.sh
source "$REPO_DIRPATH/lib.sh"

# packer and/or a --build-arg define this envar value uniformly
# for both VM and container image build workflows.
req_env_vars PACKER_BUILD_NAME

# shellcheck disable=SC2154
if [[ "$PACKER_BUILD_NAME" =~ "netavark" ]]; then
    bash $SCRIPT_DIRPATH/fedora-netavark_packaging.sh
elif [[ "$PACKER_BUILD_NAME" =~ "podman-py" ]]; then
    bash $SCRIPT_DIRPATH/fedora-podman-py_packaging.sh
elif [[ "$PACKER_BUILD_NAME" =~ "build-push" ]]; then
    bash $SCRIPT_DIRPATH/build-push_packaging.sh
    # Registers qemu emulation for non-native execution
    $SUDO systemctl enable systemd-binfmt
    for arch in amd64 s390x ppc64le arm64; do
        msg "Caching latest $arch fedora image..."
        $SUDO podman pull --quiet --arch=$arch \
            registry.fedoraproject.org/fedora:$OS_RELEASE_VER
    done
else
    bash $SCRIPT_DIRPATH/fedora_packaging.sh
fi

# Only on VMs
if ! ((CONTAINER)); then
    # Due to https://bugzilla.redhat.com/show_bug.cgi?id=2159066 we
    # cannot use kernels after 6.0.15 until bug is fixed.  Since there's
    # no simple way to compare kernel versions, just hard-code what we want.
    # TODO: Remove this entire conditional when bug is fixed
    if [[ "$OS_RELEASE_VER" -eq 37 ]]; then
      $SUDO dnf install -y kernel-6.0.7-301.fc37
      $SUDO grubby --set-default /boot/vmlinuz-6.0.7-301.fc37.$(uname -m)
    elif [[ "$OS_RELEASE_VER" -eq 36 ]]; then
      $SUDO dnf install -y kernel-5.17.5-300.fc36
      $SUDO grubby --set-default /boot/vmlinuz-5.17.5-300.fc36.$(uname -m)
    fi

    if [[ "$PACKER_BUILD_NAME" =~ netavark ]]; then
        msg "Setting up VM for netavark testing"
        echo -e '# Added during VM Image build\nsctp' |
            $SUDO tee /etc/modules-load.d/netavark_ci_sctp
    else
        msg "Enabling cgroup management from containers"
        ooe.sh $SUDO setsebool -P container_manage_cgroup true
    fi
fi

nm_ignore_cni

finalize

echo "SUCCESS!"
