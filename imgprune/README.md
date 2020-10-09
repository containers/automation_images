A container image for maintaining the collection of
deprecated VM images disused by CI/CD projects.  Images
marked deprecated are pruned (deleted) by this image
once they surpass a certain age since last-used.

Example build (from repository root):

```bash
podman build -t $IMAGE_NAME -f imgprune/Containerfile .
```
