A container image for maintaining the collection of
VM images used by CI/CD on several projects. Acts upon
metadata maintained by the `imgts` container.  Images
found to be disused, are marked obsolete (deprecated).
A future process is responsible for pruning the obsolete
images.  This workflow provides for a recovery option
should an image be erroneously obsoleted.

* `GCPJSON` - Contents of the service-account JSON key file.
* `GCPNAME` - Complete Name (fake e-mail address) of the service account.
* `GCPPROJECT` - Project ID of the GCP project.

Example build (from repository root):

```bash
make imgobsolete IMG_SFX=example
```
