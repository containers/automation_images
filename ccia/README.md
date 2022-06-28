# Cirrus-CI Artifacts

This container facilitates access to artifact files, from select tasks,
of a Cirrus-CI build.  For more details, [see the automation
documentation](https://github.com/containers/automation/blob/main/cirrus-ci_artifacts/README.md).

## Build

This is a multi-stage build with some parallelism possible if stages were
previously cached.  For example:

`podman build -t ccia --jobs=4 .`

## Usage

It is recommended that you first create a volume to store any downloaded
artifacts.

`podman volume create ccia`

Knowing a Cirrus-CI build ID, you can download all artifacts (or select
[a subset using a
regex](https://github.com/containers/automation/tree/main/cirrus-ci_artifacts#usage).
The artifacts subdirectory will be written into the `/data` volume, so
be sure it's mounted.  The `--verbose` option is shown for illustrative
purposes, it's not required.

```
BID=<Cirrus Build ID>
podman run -it --rm -v ccia:/data ccia $BID --verbose
DATA="$(podman volume inspect ccia | jq -r '.[].Mountpoint')/$BID"
ls -laR $DATA
```
