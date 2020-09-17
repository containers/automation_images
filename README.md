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

4. Strict-merging is enabled, therefore all pull requests must be kept up
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
   booted as *GCE VMs*.  In parallel, build Fedora and Ubuntu container
   images and push them to ``quay.io/libpod/<name>_podman``

3. Boot a *GCE VM* from each image produced in step 2.  Execute necessary
   scripts to customize image for use by containers-project automation.
   In other words, install packages and scripts needed for Future incarnations
   of the VM to run automated tests.


## The last part first (overview step 3)

a.k.a. ***Cache Images***

These are the VM Images actually used by other repositories for automated
testing.  So, assuming you just need to update packages or tweak the list,
start here.  Though be aware, this repository does not yet perform any testing
of the images.  That's your secondary responsibility, see step 5 below.

Notes:

* ***Warning:*** Before you go deleting seemingly "unnecessary" packages and
  "extra" code, remember these VM images are shared by automation in multiple
  repositories.

* VM configuration starts with one of the `cache_images/*_setup.sh` scripts.
   Normally you probably won't need/want to mess with these.

*  The bulk of the packaging work occurs next, from the `cache_images/*_packaging.sh`
   scripts.  This is most likely what you want to modify.

*  Some non-packaged/source-based tooling is installed using the
   `cache_images/podman_tooling.sh` script.  These are slightly fragile, as
   they always come from upstream (master) podman.  Avoid adding/changing
   anything here if alternatives exist.

Process:

1. After you make your changes, push to a PR.  Shell-script changes will be
   validated and VM image production building will begin automatically.

2. Assuming successful image-build, the name of all output images will share
   a common suffix.  To discover this suffix, find and click one of the
   `View more details on Cirrus CI` links (bottom of the *Checks* tab in github).
   Any **Cirrus-CI** task will do, it doesn't matter which you pick.

3. Toward the top of the page, is a button labeled *VIEW ALL TASKS*.
   Click this button.

4. Look at the URL in your browser, it will be of the form
   `https://cirrus-ci.com/build/<big number>`.  Copy-paste (or otherwise
   record in stone) the **big number**, you'll need it for the next step.

5. Go over to whatever other containers/repository needed the image update.
   Open the `.cirrus.yml` file, and find the 'env' line referencing the image
   suffix.  It will likely be named `_BUILT_IMAGE_SUFFIX:` or something similar.

7. Paste in the **big number** *prefixed by the letter 'c'*.  The *"c*" indicates
   the images are *cache images*.  For example, if the url was `http://.../12345`
   you would paste in `c12345` as the value for `_BUILT_IMAGE_SUFFIX:`.

8. Open up a PR with this change, and push it.  Once all tests pass and you're
   satisfied with the image changes, ask somebody to review/approve both
   PRs for merging.  If you're feeling generous, perhaps provide cross-links
   between the two PRs in comments, for future reference.

9. After all the PRs are merged, you're done.




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

4. Packer will spin up a GCE VM based on CentOS. It will then install the
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


## The Base Images (overview step 2)

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


## Container images (Also overview step 2)

In parallel with other tasks, several instances of the image-builder VM are
used to create container images.  In particular, Fedora and Ubuntu
images are created that more-or-less duplicate the setup of the VM
Cache-images.  They are then automatically pushed to:

* https://quay.io/repository/libpod/fedora_podman
* https://quay.io/repository/libpod/prior-fedora_podman
* https://quay.io/repository/libpod/ubuntu_podman
* https://quay.io/repository/libpod/prior-ubuntu_podman

The meaning of *prior* and not, is defined by the contents of the `*_release`
files within the `podman` subdirectory.


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
