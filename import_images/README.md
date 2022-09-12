# Semi-manual image imports

## Overview

[Due to a bug in
packer](https://github.com/hashicorp/packer-plugin-amazon/issues/264) and
the sheer complexity of EC2 image imports, this process is impractical for
full automation.  It tends toward nearly always requiring supervision of a
human:

* There are multiple failure-points, some are not well reported to
  the user by tools here or by AWS itself.
* The upload of the image to s3 can be unreliable.  Silently corrupting image
  data.
* The import-process is managed by a hosted AWS service which can be slow
  and is occasionally unreliable.
* Failure often results in one or more leftover/incomplete resources
  (s3 objects, EC2 snapshots, and AMIs)

## Requirements

* You're generally familiar with the (manual)
  [EC2 snapshot import process](https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-import-snapshot.html).
* You are in possession of an AWS EC2 account, with the [IAM policy
  `vmimport`](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html#vmimport-role) attached.
* Both "Access Key" and "Secret Access Key" values set in [a credentials
  file](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html).
* Podman is installed and functional
* At least 10gig free space under `/tmp`, more if there are failures / multiple runs.
* *Network bandwidth sufficient for downloading and uploading many GBs of
  data, potentially multiple times.*

## Process

Unless there is a problem with the current contents of the
imported images, this process does not need to be followed.  The
normal PR-based build workflow can simply be followed as usual.

***Note:*** Most of the steps below will happen within a container environment.
Any exceptions are noted in the individual steps below with *[HOST]*

1. *[HOST]* Edit the `Makefile`, update release numbers and/or URLs
   under the section
   `##### Important image release and source details #####`
1. *[HOST]* Run
   ```bash
   $ make image_builder_debug \
         IMG_SFX=$(date +%s) \
         GAC_FILEPATH=/dev/null \
         AWS_SHARED_CREDENTIALS_FILE=/path/to/.aws/credentials
   ```
1. Run `make import_images`
1. The following steps should all occur successfully for each imported image.
   1. Image is downloaded.
   1. Image checksum is downloaded.
   1. Image is verified against the checksum.
   1. Image is converted to `VHDX` format.
   1. The `VHDX` image is uploaded to the `packer-image-import` S3 bucket.
   1. AWS `import-snapshot` process is started.
   1. Progress of snapshot import is monitored until completion or failure.
   1. The imported snapshot is converted into an AMI
   1. Essential tags are added to the AMI
   1. Full details about the AMI are printed
1. Assuming all image imports were successful, a success message will be
   printed by `make` with instructions for updating the `Makefile`.
1. *[HOST]* Update the `Makefile` as instructed, commit the
   changes and push to a PR.  The automated image building process
   takes over and runs as usual.

## Failure responses

This list is not exhaustive, and only represents common/likely failures.
Normally there is no need to exit the build container.

* If image download fails, double-check the URL values, run `make clean`
  and retry.
* If checksum validation fails,
  double-check the URL values.  If
  changes made, run `make clean`.
  Retry `make import_images`.
* If s3 upload fails,
  double-check the URL values.  If
  changes were needed, run `make clean`.
  Retry `make import_images`.
* If snapshot import fails with a `Disk validation failed` error,
  Retry `make import_images`.
* If snapshot import fails with an error, find them in EC2 and delete them.
  Retry `make import_images`.
* If AMI registration fails, remove any conflicting AMIs and snapshots.
  Retry `make import_images`.
* If import was successful but AMI tagging failed, manually add
  the required tags to AMI: `automation=false` and `Name=<name>-i${IMG_SFX}`.
  Where `<name>` is `fedora-aws` or `fedora-aws-arm64`.
