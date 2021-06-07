A container image for tracking automation metadata.
This is used to update last-used timestamps on
VM images to prevent them from being pruned.

Required environment variables:
* `GCPJSON` - Contents of the service-account JSON key file.
* `GCPNAME` - Complete Name (fake e-mail address) of the service account.
* `GCPPROJECT` - Project ID of the GCP project.
* `IMGNAMES` - Whitespace separated list of image names to update.
* `BUILDID` - Cirrus CI build ("job") ID number for auditing purposes.
* `REPOREF` - Repository name that ran the build.

Example build (from repository root):

```bash
make imgts IMG_SFX=example
```
