A container image for tracking automation metadata.
This is used to update last-used timestamps on
VM images to prevent them from being pruned.

Example build (from repository root):

```bash
podman build -t $IMAGE_NAME -f imgts/Containerfile .
```
