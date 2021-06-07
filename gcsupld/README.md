A container image for uploading a file to Google Cloud Storage
(GCS).  It requires the caller to posess both a service-account
credentials file, volume-mount the file to be uploaded, and
provide the full destination URI. The `<BUCKET NAME>` must
already exist, and `<OBJECT NAME>` may include a pseudo-path and/or
object filename.

Required environment variables:
* `GCPJSON` - Contents of the service-account JSON key file.
* `GCPNAME` - Complete Name (fake e-mail address) of the service account.
* `GCPPROJECT` - Project ID of the GCP project.
* `FROM_FILEPATH` - Full path to volume-mounted file to upload.
* `TO_GCSURI` - Destination URI in the format `gs://<BUCKET NAME>/<OBJECT NAME>`

Example build (from repository root):

```bash
make gcsupld IMG_SFX=example
```
