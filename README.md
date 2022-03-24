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

3. Please create new pull-requests as **drafts** and/or mark them with a
   `WIP:` title-prefix while you're working on them.

4. Strict-merging is enabled, therefore all pull requests must be kept up
   to date with the base branch (i.e. re-based).


# Automation-control Magic strings

Not all changes require building and testing every container and VM
image.  For example, changes that only affect documentation.  When
this is the case, pull-requests may include ***one*** of the following
magic strings in their *title* text:

* `[CI:DOCS]` - Only perform steps necessary for general validation.
  Checking the actual documentation text is left up to human reviewers.

* ***OR***

* `[CI:TOOLING]` - Only perform validation steps, then [build and test
  the tooling container images](README.md#tooling) only.


# Building VM Images

## Process Overview

There are four parts to the automated (and manual) process.  For the [vast
majority of cases, **you will likely only be interested in the forth (final)
step**](README.md#the-last-part-first-overview-step-4).
However, all steps are listed below for completeness.

For more information on the overall process of importing custom GCE VM
Images, please [refer to the documentation](https://cloud.google.com/compute/docs/import/import-existing-image).  For more information on the primary tool
(*packer*) used for this process, please [see it's
documentation](https://www.packer.io/docs).

1. [Build and import a VM image](README.md#the-image-builder-image-overview-step-1)
    with necessary packages and metadata for
   running nested VMs.  For details on why this step is necessary,
   please [refer to the
   documentation](https://cloud.google.com/compute/docs/instances/enable-nested-virtualization-vm-instances#enablenestedvirt).

2. Two types of container images are built. The [first set includes both
   current and "prior" flavor of Fedora](README.md#podman). The
   [second set is of tooling container
   images](README.md#tooling).  Tooling required for VM image
   maintenance, artifact uploads, and debugging.

3. [Boot a *GCE VM* running the image-builder-image (from step
   1)](README.md#the-base-images-overview-step-3).
   Use this VM to
   [build and then import base-level VM
   image](README.md#the-base-images-overview-step-3) for supported platforms
   (Fedora or Ubuntu; as of this writing).  In other words, convert
   generic distribution provided VM Images, into a form capable of being
   booted as *GCE VMs*.  In parallel, build Fedora and Ubuntu container
   images and push them to ``quay.io/libpod/<name>_podman``

4. [Boot a *GCE VM* from each image produced in step
   3](README.md#the-last-part-first-overview-step-4).
   Execute necessary
   scripts to customize image for use by containers-project automation.
   In other words, install packages and scripts needed for Future incarnations
   of the VM to run automated tests.


## The last part first (overview step 4)

a.k.a. ***Cache Images***

These are the VM Images actually used by other repositories for automated
testing.  So, assuming you just need to update packages or tweak the list,
[start here](README.md#process).  Though be aware, this repository does not
yet perform any testing of the images.  That's your secondary responsibility,
see step 4 below.

**Notes:**

* VM configuration starts with one of the `cache_images/*_setup.sh` scripts.
  Normally you probably won't need/want to mess with these.

* The bulk of the packaging work occurs next, from the `cache_images/*_packaging.sh`
  scripts.  **This is most likely what you want to modify.**

* Unlike the Fedora and Ubuntu scripts, the `build-push` VM image is not
  for general-purpose use.  It's intended to be used by it's embedded
  `main.sh` script, in downstream repositories for building container images.
  The image and `main.sh` are both tightly coupled with `build-push` tool
  in the
  [containers/automation repository](https://github.com/containers/automation).

* Some non-packaged/source-based tooling is installed using the
  `cache_images/podman_tooling.sh` script.  These are slightly fragile, as
  they always come from upstream (master) podman.  Avoid adding/changing
  anything here if alternatives exist.

* **Warning:** Before you go deleting seemingly "unnecessary" packages and
  "extra" code, remember these VM images are shared by automation in multiple
  repositories.


### Process: ###

1. After you make your script changes, push to a PR.  They will be
   validated and linted before VM image production begins.

2. The name of all output images will share a common suffix (*image ID*).
   Assuming a successful image-build, a
   [github-action](.github/workflows/pr_image_id.yml)
   will post the new *image ID* as a comment in the PR.  If this automation
   breaks, you may need to [figure the ID out the hard
   way](README.md#Looking-up-an-image-ID).

3. Go over to whatever other containers/repository needed the image update.
   Open the `.cirrus.yml` file, and find the 'env' line referencing the *image
   ID*.  It will likely be named `IMAGE_SUFFIX:` or something similar.
   Paste in the *image ID*.

4. Open up a PR with this change, and push it.  Once all tests pass and you're
   satisfied with the image changes, ask somebody to review/approve both
   PRs for merging.  If you're feeling generous, perhaps provide cross-links
   between the two PRs in comments, for future reference.

9. After all the PRs are merged, you're done.


### Looking up an image ID: ###

An *image ID* is simplya big number prefixed by the letter 'c'.  You may
need to look it up in a PR for example, if
[the automated comment posting github-action](.github/workflows/pr_image_id.yml)
fails.

1. In a PR, find and click one of the `View more details on Cirrus CI`
   links (bottom of the *Checks* tab in github). Any **Cirrus-CI** task
   will do, it doesn't matter which you pick.

2. Toward the top of the page, is a button labeled *VIEW ALL TASKS*.
   Click this button.

3. Look at the URL in your browser, it will be of the form
   `https://cirrus-ci.com/build/<big number>`.  Copy-paste (or otherwise
   record in stone) the **big number**, you'll need it for the next step.

4. The new *image ID* is formed by prefixing the **big number** with the
   the letter *"c*".  For example, if the url was `http://.../12345`
   the *image ID* would be `c12345`.


## The image-builder image (overview step 1)

Google compute engine (GCE) does not provide a wide selection of ready-made
VM images for use.  Instead, a lengthy and sophisticated process is involved
to prepare, properly format, and import external VM images for use.  In order
to perform these steps within automation, a dedicated VM image is needed which
itself has been prepared with the necessary incantations, packages, configuration,
and magic license keys.

For normal day-to-day use, this process should not need to be modified or
maintained much.  However, on the off-chance that's ever not true, here is
an overview of the process followed **by automation** to produce the
*image-building VM image*:

1. Build the container defined in the `ci` subdirectory's `ContainerFile`.
   Start this container with a copy of the current repository code provided
   in the `$CIRRUS_WORKING_DIR` directory. For example on a Fedora host:

   ```
   podman run -it --rm --security-opt label=disable -v $PWD:$PWD -w $PWD ci_image
   ```

2. From within the `ci` container (above), in the repository root volume, execute
   the  `make image_builder` target.

3. The `image_builder/gce.yml` file is converted into JSON format for
   consumption by the [Hashicorp *packer* utility](https://www.packer.io/).
   This generated file may be ignored, *make* will be regenerate it upon
   any changes to the YAML file.

4. Packer will spin up a GCE VM based on CentOS Stream. It will then install the
   necessary packages and attach a [nested-virtualization "license" to the
   VM](https://cloud.google.com/compute/docs/instances/enable-nested-virtualization-vm-instances#enablenestedvirt).  Be patient until this process completes.

5. Near the end of the process, packer deletes temporary files, ssh host keys,
   etc. and then shut down the GCE VM.

6. Packer should then automatically call into the google cloud APIs and
   coordinate conversion of the VM disk into a bootable image.  Please
   be patient for this process to complete, it may take several minutes.

7. When finished, packer will write the freshly created image name and other
   metadata details into the local `image_builder/manifest.json` file for
   reference and future use.  The details may be useful for debugging, or
   the file can be ignored/disregarded.

8. Automation scoops up the `manifest.json` file and archives it along with
   the build logs.


## Container images (overview step 2)


### Podman

Several instances of the image-builder VM are used to create container
images.  In particular, Fedora and Ubuntu images are created that
more-or-less duplicate the setup of the VM Cache-images.  They are
then automatically pushed to:

* https://quay.io/repository/libpod/fedora_podman
* https://quay.io/repository/libpod/prior-fedora_podman
* https://quay.io/repository/libpod/ubuntu_podman

The meaning of *prior* and *current*, is defined by the contents of
the `*_release` files within the `podman` subdirectory.  This is
necessary to support the Makefile target being used manually
(e.g. debugging).  These files must be updated manually when introducing
a new VM image version.


### Tooling

In addition to the "podman" container images, several automation tooling images
are also built.  These are always referenced by downstream using their
"latest" tag (unlike the podman and VM images).  In addition to
the [VM lifecycle tooling images](README.md#vm-image-lifecycle-management),
the following are built:

* `gcsupld` image is used for publishing artifacts into google cloud storage.

* `get_ci_vm` image is used indirectly from the containers-org. repositories
  script `hack/get_ci_vm.sh` script.  It should never be used directly.

In all cases, when automation runs on a branch (i.e. after a PR is merged)
the actual image tagged `latest` will be pushed.  When running in a PR,
only validation and test images are produced.  This behavior is controled
by a combination of the `$PUSH_LATEST` and `$CIRRUS_PR` variables.


## The Base Images (overview step 3)

VM Images in GCE depend upon certain google-specific systemd-services to be
running on boot.  Additionally, in order to import external OS images,
google needs a specific partition and archive file layout.  Lastly,
importing images must be done indirectly, through [Google Cloud
Storage (GCS)](https://cloud.google.com/storage/docs/introduction).  As with
the image-builder image, this process is mainly orchestrated by Packer:

1. A GCE VM is booted from the image-builder image, produced in *overview step 1*.

2. On the image-builder VM, the (upstream) generic-cloud images for each
   distribution are downloaded and verified.  *This is very networking-intense.*

3. The image-builder VM then boots (nested) KVM VMs for the downloaded
   images.  These local VMs are then updated, installed, and prepared
   with the necessary packages and services as described above. *This
   is very disk and CPU intense*.

4. All the automation-deities pray with us, that the nested VMs setup
   correctly and completely.  Debugging them can be incredibly difficult
   and painful.

5. Packer (running on the image-builder VM), shuts down the nested VMs,
   and performs the import/conversion process.  Creating compressed tarballs,
   uploading to GCS, then importing into GCP VM images.

7. Packer deletes the VM, and writes the freshly created image name and other
   metadata details into a `image_builder/manifest.json` file for reference.

8. Automation scoops up the `manifest.json` file and archives it along with
   the build logs.


## VM Image lifecycle management

There is no built-in mechanism for removing disused VM images in GCP. Nor is
there any built-in tracking information, recording which VM images are
currently being used by one or more containers-repository automation.
Three containers and two asynchronous processes are responsible for tracking
and preventing infinite-growth of the VM image count.

* `imgts` Runs as part of automation for every repository, every time any
  VM is utilized.  It records the usage details, along with a timestamp
  into the utilized VM image "labels" (metadata).  Failure to update
  metadata is considered critical, and the task will fail to prompt
  immediate corrective action by automation maintainers.

* `imgobsolete` is triggered periodically by cron *only* on this
  repository. It scans through all VM Images, filtering any which
  haven't been used within the last 30 days (according to `imgts`
  updated labels). Identified images are deprecated by marking them
  `obsolete` in GCE.  This status blocks them from being used, but
  does not actually remove them.

* `imgprune` also runs periodically, immediately following `imgobsolete`.
  It scans all currently obsolete images, filtering any which were
  deprecated more than 30 days ago (according to deprecation metadata).
  Images which have been obsolete for more than 30 days, are permanently
  removed.


# Debugging / Locally driving VM Image production

Because the entire automated build process is containerized, it may easily be
performed locally on your laptop/workstation.  However, this process will
still involve interfacing with GCP and GCS.  Therefore, you must be in possession
of a *Google Application Credentials* (GAC) JSON file.

The GAC JSON file should represent a service account (contrasted to a user account,
which always uses OAuth2).  The name of the service account doesn't matter,
but it must have the following roles granted to it:

* Compute Instance Admin (v1)
* Compute OS Admin Login
* Service Account User
* Storage Admin
* Storage Object Admin

Somebody familiar with Google IAM will need to provide you with the GAC JSON
file and ensure correct service account configuration.  Having this file
stored *in your home directory* on your laptop/workstation, the process of
producing images proceeds as follows:

1. Invent some unique identity suffix for your images.  It may contain (***only***)
   lowercase letters, numbers and dashes; nothing else.  Some suggestions
   of useful values would be your name and todays date.  If you manage to screw
   this up somehow, stern errors will be presented without causing any real harm.

2. Ensure you have podman installed, and lots of available network and CPU
   resources (i.e. turn off YouTube, shut down background VMs and other hungry
   tasks).  Build the image-builder container image, by executing
   ``make image_builder_debug GAC_FILEPATH=</home/path/to/gac.json> IMG_SFX=<UUID chosen in step 1>``

3. You will be dropped into a debugging container, inside a volume-mount of
   the repository root.  This container is practically identical to the VM
   produced and used in *overview step 1*.  If changes are made, the container
   image should be re-built to reflect them.

4. If you wish to build only a subset of available images, list the names
   you want as comma-separated values of the `PACKER_BUILDS` variable.  Be
   sure you *export* this variable so that `make` has access to it.  For
   example, `export PACKER_BUILDS=ubuntu,prior-fedora`.

4. Still within the container, again ensure you have plenty of network and CPU
   resources available.  Build the VM Base images by executing the command
   ``make base_images``. This is the equivalent operation as documented by
   *overview step 2*.  ***N/B*** The GCS -> GCE image conversion can take
   some time, be patient.  Packer may not produce any output for several minutes
   while the conversion is happening.

5. When successful, the names of the produced images will all be referenced
   in the `base_images/manifest.json` file.  If there are problems, fix them
   and remove the `manifest.json` file.  Then re-run the same *make* command
   as before, packer will force-overwrite any broken/partially created
   images automatically.

6. Produce the GCE VM Cache Images, equivalent to the operations outlined
   in *overview step 3*.  Execute the following command (still within the
   debug image-builder container): ``make cache_images``.

7. Again when successful, you will find the image names are written into
   the `cache_images/manifest.json` file.  If there is a problem, remove
   this file, fix the problem, and re-run the `make` command.  No cleanup
   is necessary, leftover/disused images will be automatically cleaned up
   eventually.
