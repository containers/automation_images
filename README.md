# README.md

This repository holds the configuration for automation-related VM and
container images.  CI/CD automation in this repo. revolves around
producing new images. It does only very minimal testing of image
suitability for use by other *containers* org. repos.

# Contributing

1. Thanks!

2. This repo. follows the [fork & pull
   model](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request-from-a-fork)
   When ready for review, somebody besides the author must click the green
   *Review changes* button within the PR.

3. ***IMPORTANT***: **Automatic pull-requests merging is enabled on this repository!
   Pull requests will be merged automatically when they:**

   * Are not marked as a draft
   * Have at least ***one*** approving github review.
   * Pass the 'success' test

4. Strict-merging is enabled, therefor all pull requests must be kept up
   to date with the base branch.  The [Mergify bot can help with
   this.](https://doc.mergify.io/commands.html#commands)


# Building VM Images

## Process Overview

There are three parts to the automated (and manual) process.  For the vast
majority of cases, **you will likely only be interested in the third (final)
step**.  However, all steps are listed below for completeness.

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


# The last step

Assuming all you need to do is tweak the package list, add or adjust a makefile
target, start here.  Before you go deleting all the seemingly "unnecessary" and
"extra" packages, please remember these VM images are shared by automation
in multiple repositories :D

1. VM configuration starts with one of the `cache_images/*_setup.sh` scripts.
   Normally you probably won't need/want to mess with these.

2. The bulk of the packaging work occurs next, from the `cache_images/*_packaging.sh`
   scripts.  This is most likely what you want to modify.

3. Lastly, some non-packaged/source-based tooling is installed, using the
   `cache_images/podman_tooling.sh` script.

4. After you make your changes, push to a PR.  Shell-script changes will be
   automatically validated, and then VM image building will begin.

5. After a successful build, the name of each output image will share a common
   suffix.  To discover this suffix, find and click one of the
   `View more details on Cirrus CI` links at the bottom of the *Checks* tab.
   Any **Cirrus-CI** task will do, it doesn't matter which you pick.

6. Toward the top of the page, is a button with an arrow, that reads
   *VIEW ALL TASKS*.  Click this button.

7. Look at the URL in your browser, it will use the form
   `https://cirrus-ci.com/build/<big number>`.  Copy-paste (or otherwise
   record in stone) the *big number*, you'll need it for the next step.

6. Go over to whatever other containers/repository needed the image update.
   Open the `.cirrus.yml` file, and paste the *big number* in place of the
   value next to `_BUILT_IMAGE_SUFFIX:`.  Open up a PR with this change,
   and push it.

7. Once all other PR's tests pass and your satisfied with the image changes,
   ask somebody to review/approve the *automation_images* PR so it can merge.
   If you're feeling generous, perhaps provide cross-links between the two
   PRs for future reference.

8. After all the PRs are merged, you're done.  You may now attend to the little
   dog begging you for a walk for the last hour.  Hurry!  Little-dogs, do not
   have big-dog bladders!
