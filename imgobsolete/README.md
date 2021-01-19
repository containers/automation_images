A container image for maintaining the collection of
VM images used by CI/CD on several projects. Acts upon
metadata maintained by the `imgts` container.  Images
found to be disused, are marked obsolete (deprecated).
A future process is responsible for pruning the obsolete
images.  This workflow provides for a recovery option
should an image be erroneously obsoleted.

Example build (from repository root):

```bash
make imgobsolete IMG_SFX=example
```
