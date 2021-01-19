A container image for uploading a file to Google Cloud Storage
(GCS).  It requires the caller to posess both a service-account
credentials file, volume-mount the file to be uploaded, and
provide the full destination URI using the format:
`gs://<BUCKET NAME>/<OBJECT NAME>`.  Where `<BUCKET NAME>` must
already exist, and `<OBJECT NAME>` may include a pseudo-path and/or
object filename.

Example build (from repository root):

```bash
make gcsupld IMG_SFX=example
```
