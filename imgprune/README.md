A container image for maintaining the collection of
VM images used by CI/CD on several projects. Acts upon
metadata maintained by the imgts container.

Example build (from repository root):

```bash
podman build -t $IMAGE_NAME -f imgprune/Containerfile .
```
