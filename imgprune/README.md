A container image for maintaining the collection of
deprecated VM images disused by CI/CD projects.  Images
marked deprecated are pruned (deleted) by this image
once they surpass a certain age since last-used.

* `GCPJSON` - Contents of the service-account JSON key file.
* `GCPNAME` - Complete Name (fake e-mail address) of the service account.
* `GCPPROJECT` - Project ID of the GCP project.

Example build (from repository root):

```bash
make imgprune IMG_SFX=example
```
