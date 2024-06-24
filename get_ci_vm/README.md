# Overview

This directory contains the source for building [the
`quay.io/libpod/get_ci_vm:latest` image](https://quay.io/repository/libpod/get_ci_vm?tab=info).
This image image is used by many containers-org repos. `hack/get_ci_vm.sh` script.
It is not intended to be called via any other mechanism.

In general/high-level terms, the architecture and operation is:

1. [containers/automation hosts cirrus-ci_env](https://github.com/containers/automation/tree/main/cirrus-ci_env),
   a python mini-implementation of a `.cirrus.yml` parser. It's only job is to extract all required envars,
   given a task name (including from a matrix element).  It's highly dependent on
   [certain YAML formatting requirements](README.md#downstream-repository-cirrusyml-requirements).  If the target
   repo. doesn't follow those standards, nasty/ugly python errors will vomit forth.  Mainly this has to do with
   Cirrus-CI's use of a non-standard YAML parser, allowing things like certain duplicate dictionary keys.
1. [containers/automation_images hosts get_ci_vm](https://github.com/containers/automation_images/tree/main/get_ci_vm),
   a bundling of the `cirrus-ci_env` python script with an `entrypoint.sh` script inside a container image.
1. When a user runs `hack/get_ci_vm.sh` inside a target repo, the container image is entered, and `.cirrus.yml`
   is parsed based on the CLI task-name.  A VM is then provisioned based on specific envars (see the "Env. Vars."
   entries in the sections for [APIv1](README.md#env-vars) and [APIv2](README.md#env-vars-1) sections below).
   This is the most complex part of the process.
1. The remote system will not have **any** of the otherwise automatic Cirrus-CI operations performed (like "clone")
   nor any magic CI variables defined.  Having a VM ready, the container entrypoint script transfers a copy of
   the local repo (including any uncommited changes).
1. The container entrypoint script then performs **_remote_** execution of the `hack/get_ci_vm.sh` script
   including the magic `--setup` parameter.  Though it varies by repo, typically this will establish everything
   necessary to simulate a CI environment, via a call to the repo's own `setup.sh` or equivalent.  Typically
   The repo's setup scripts will persist any required envars into a `/etc/ci_environment` or similar.  Though
   this isn't universal.
1. Lastly, the user is dropped into a shell on the VM, inside the repo copy, with all envars defined and
   ready to start running tests.

_Note_:  If there are any envars found to be missing, they must be defined by updating either the repo normal CI
setup scripts (preferred), or in the `hack/get_ci_vm.sh` `--setup` section.

# Building

Example build (from repository root):

```bash
make get_ci_vm IMG_SFX=latest
podman tag get_ci_vm:latest quay.io/libpod/get_ci_vm:latest
```

# Operational details

The container expects to be called in a specific way, by a script which
itself needs to behave according to a set of rules (outlined below).
This bidirectional requirement scheme is necessary to properly support
differing runtime details and requirements across multiple repositories.

## Downstream repository `.cirrus.yml` requirements

1. *Must* be valid YAML parsable by a **standard** parser.
1. *Must not* rely on [a `Starlark` script](https://cirrus-ci.org/guide/programming-tasks/).
1. *Must not* have any conflicting/overlapping task or alias names.  If a matrix
   modification is used, unique names or aliases *must* be defined for every axis.
1. For any tasks executing in GCE, the instance parameters (CPU, memory, etc)
   should be the same or lower than those defined by the hack script's
   [`GCLOUD_CPUS`, `GCLOUD_MEMORY`, and `GCLOUD_DISK`
   values](README.md#env-vars).
1. For any tasks executing in AWS EC2, the **`EC2_INST_TYPE`** env. var.
   *must* be defined.  Either globally or locally within the task.
1. Any operational prerequisites (such as use of build-cache) *must* be
   separately satisfied by [the hack script's `--setup`
   interface](README.md#hack-script-requirements).  This
   is because get_ci_vm is not intelligent enough to follow task dependencies,
   nor execute any `clone_script`, `always`, `artifact_*`, or `script_*`
   instructions.

## Downstream repository hack-script requirements

1. The calling script *must* be named `hack/get_ci_vm.sh` and set executable.
1. The script *must* execute a `get_ci_vm` container built from the
   c/automation_images repository `main` branch, or a PR (for testing).
1. The script must define the following env. vars **if they are not already set**.:
   1. `NAME` - *Must* contain the value of `$USER` on the host, which *must not*
      be `root`.
      The value *must* be valid as a "name" component of any VM created in any cloud.
   1. `SRCDIR` - *Must* be set to the repository bind-mount location inside the container
      (see **repository-path** mount, in the next top-level item below)
   1. `GCLOUD_ZONE` - Should be set to a valid GCE zone, network-near the users
      location.  Valid values are listed in [the GCE
      documentation](https://cloud.google.com/compute/docs/regions-zones/#available).
      This is optional, though it does make some network operations faster for
      the user.
   1. `A_DEBUG` - *May* be set to `1` to enable printing of (lots) debugging details.
      Otherwise it should be unset, empty, or `0`.
1. The script *must* execute the `get_ci_vm` container with the following bind-mount
   volumes:
   1. The **repository-path** containing the exact same `hack/get_ci_vm.sh` front-end
      being run by the user.  This *must* be mounted inside the container at the
      path set in the `$SRCDIR` env. var. (see above).  It *may* be (highly recommended)
      mounted with the `O` overlay option to protect local contents.  It's assumed
      the repository is in the state desired by the user to reproduce on the remote VM.
      Any commited or uncommited changes will be preserved and transfered as-is.
   1. The `$HOME/.config/gcloud` directory *must* exist, and be mounted inside
      the container at `/root/.config/gcloud` (with the `z` option).
      Repository-specific GCE settings and (sensitive) credentials are stored here.
      Though they will be maintained using destinct configuration profile names,
      contents should be protected as if they were passwords.  i.e. Never commit them
      into any container image or provide them publically.
   1. The `$HOME/.config/gcloud/ssh` directory *must* exist, and be mounted
      inside the container at `/root/.ssh` (with the `z` option).  This directory
      will hold auto-maintained ssh keys for accessing VMs in both GCE and EC2.
      Removing these files is generally safe, as they will be re-generated on
      next execution.
   1. The `$HOME/.aws` directory *must* exist, and be mounted inside the container
      at `/root/.aws` (with the `z` option).  This directory will contain AWS
      specific settings, maintained with destinct profile names similar to GCE.
      Similar to `$HOME/.config/gcloud`, contents should be protected and treated
      as if they were passwords.

## APIv1 (GCE Support)

### Hack-script requirements

1. Somewhere within the script the string `# get_ci_vm APIv1` *must* be present.
1. Any command-line arguments passed to the `hack/get_ci_vm.sh` script *must* be
   passed as-is into the container as arguments, with the following exceptions:
   1. When called with the `--config` option, the script *must*:
      1. Confirm `$GET_CI_VM` is `1`.  This signifies the script is executing
         from **within** the get_ci_vm container context with API version
         `1` env. var. expectations (see next item)
      1. Print on *stdout*, a list of `key=value` env. var lines conforming
         to [the *APIV1 Env. Vars.* section below](README.md#env-vars).
      1. Exit non-zero if there is an error.
   1. When called with the `--setup` option, the script should:
      1. Confirm `$GET_CI_VM` is non-zero (i.e. any API version greater than `1`).
         This signifies the script is (now) executing from **within** a newly
         created VM with CWD undefined.
      1. Execute any commands necessary (on the VM) to prepare it for
         use by the user. For example, this could include calling *make* targets
         and/or environment-setup scripts like `./contrib/cirrus/setup.sh`.
      1. Exit non-zero if there is an error.

### Env. Vars.

When `hack/get_ci_vm.sh` is executed with the `--config` argument, it
*must* emit a `key=value` list of env. vars. to *stdout* if and only if
the `$GET_CI_VM` value is set to `1`.  For any other value, please refer to
the corresponding API version section in this doc.

* `DESTDIR` - *Must* be set to the "clone" directory (on the VM) for the
  repository's code.  This directory is analogous to the `$CIRRUS_WORKING_DIR`
  value in `.cirrus.yml`.  It will be created if it doesn't exist, and
  a copy of the user's repository will be presented, under a `get_ci_vm`
  branch.
* `UPSTREAM_REPO` - *Must* be set to the upstream clone URL for the repository.
  This will be set as a remote and fetched (on the VM) to facilitate use of the
  VM.  It's also used to prevent uploading large amounts of data from the user's
  local system.
* `CI_ENVFILE` - This *may* point to a file containing any CI-runtime env. vars.
  which should also be present in the (eventual) remote shell for the user.
  For example, the podman repository's `./contrib/cirrus/setup_environment.sh`
  populates a `/etc/ci_environment` file with important CI setup-time values.
* `GCLOUD_PROJECT` - *Must* contain the name of the GCE project space where
  the VM will be created.
* `GCLOUD_IMGPROJECT` - *Must* be set to `libpod-218412` (the GCE project space
  containing all the VM images).
* `GCLOUD_CFG` - *Must* be set to the name of the GCE configuration to maintain
  for this repository.  See the GCE settings bind-mount item under
  the *Operational Details* section above.
* `GCLOUD_ZONE` - *Must* be set to either `us-central1-a` or any valid network-near
  zone to the user.   Valid values are listed in [the GCE
  documentation](https://cloud.google.com/compute/docs/regions-zones/#available)
* `GCLOUD_CPUS` - *Must* be set to the number of vCPUs to assign to the VM.
* `GCLOUD_MEMORY` - *Must* be set to the amount of memory to assign to the VM.
* `GCLOUD_DISK` - *Must* be set to `200` (gigabytes).

## APIv2 (AWS EC2 Support)

### Hack-script requirements

1. Somewhere within the script the string `# get_ci_vm APIv2` *must* be present.
1. All the command-line requirements of APIv1.
1. Any command-line arguments passed to the `hack/get_ci_vm.sh` script *must* be
   passed as-is into the container as arguments, with the following exceptions:
   1. When called with the `--config` option, the script *must*:
      1. Confirm `$GET_CI_VM` is `2`.  This signifies the script is executing
         from **within** the get_ci_vm container context with API version
         `2` env. var. expectations (see next item)
      1. Print on *stdout*, a list of `key=value` env. var lines conforming
         to [the *APIV2 Env. Vars.* section below](README.md#env-vars-1).
      1. Exit non-zero if there is an error.
   1. When called with the `--setup` option, the script should:
      1. Confirm `$GET_CI_VM` is non-zero (i.e. any API version greater than `1`).
         This signifies the script is (now) executing from **within** a newly
         created VM with CWD undefined.
      1. Execute any commands necessary (on the VM) to prepare it for
         use by the user for any `$GET_CI_VM` API version upto and including `2`.
      1. Exit non-zero if there is an error.

### Env. Vars.

When `hack/get_ci_vm.sh` is executed with the `--config` argument, it
*must*:

1. Confirm the value of `$GET_CI_VM` is set to `2`.
1. Emit a line containing `AWS_PROFILE=containers`.  This defines
   the AWS profile name to use for configuration and credentials.

***N/B:*** The repository's `.cirrus.yml` **must** define a
**`EC2_INST_TYPE`** env. var. for any EC2-based tasks or globally. Any
EC2-based task which does not resolve a value for this variable is assumed
as "unsupported) (for `hack/get_ci_vm.sh`) and an appropriate error will
be returned.
