# README.md

This repository holds the configuration for automation-related VM and
container images.  CI/CD automation in this repo. revolves around
producing new images. It does only very minimal testing of image
suitability for use by other *containers* org. repos.

# Contributing

1. Thanks!

2. ***IMPORTANT***: **Automatic pull-requests merging is enabled on this repository!
   Pull requests will be merged automatically when they:**

   * Are not marked as a draft (*see below*)
   * Have at least one approving github review.
   * Pass the 'success' test

3. Pull requests that are not ready for review, must be marked as *draft*.
   This can be accomplished either:

   * When a pull-request is first submitted via the Github WebUI. Click
     the drop-down menu next to the green 'Create pull request' button.
     Select the value **Create draft pull request**.  Click the button.

   * At any time after creation, by clicking the **convert to draft**
     link located in the upper-right of the pull-request page, under
     'Reviewers'.

4. This repo. follows the [fork & pull
   model](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request-from-a-fork)

5. Strict-merging is enabled to guarantee the tip of the base branch has
   always been checked by automation.  All pull requests must be kept up
   to date with the base branch.  The [Mergify bot can help with
   this.](https://doc.mergify.io/commands.html#commands)

# Building VM Images

## Process Overview

There are three parts to the automated (and manual) process.  For the vast
majority of cases, you will only be interested in the third (final) step.
All steps are listed here for completeness.

For more information on the overall process of importing custom GCE VM
Images, please [refer to the documentation](https://cloud.google.com/compute/docs/import/import-existing-image).  For more information on the primary tool
(*packer*) used for this process, please [see it's
documentation](https://www.packer.io/docs).


1. Build and import a VM image with necessary packages and metadata for
   running nested VMs.  For details on why this step is necessary,
   please [refer to the
   documentation](https://cloud.google.com/compute/docs/instances/enable-nested-virtualization-vm-instances#enablenestedvirt).

2. Boot a *GCE VM* running the image produce in step 1.  Use this VM to
   build and then import base-level VM image for supported platforms
   (Fedora or Ubuntu; as of this writing).  In other words, convert
   generic distribution provided VM Images, into a form capable of being
   booted as *GCE VMs*.

3. Boot a *GCE VM* from each image produced in step 2.  Execute necessary
   scripts to customize image for use by containers-project automation.
   In other words, install packages and scripts needed for Future incarnations
   of the VM to run automated tests.
