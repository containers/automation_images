A container image for use by containers-org repos.
`hack/get_ci_vm.sh` script.  It should not be
used via any other mechanism.

Example build (from repository root):

```bash
make get_ci_vm IMG_SFX=latest
podman tag get_ci_vm:latest quay.io/libpod/get_ci_vm:latest
```
