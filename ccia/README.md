# Cirrus-CI Artifacts

This container facilitates access to artifact files, from select tasks,
of a Cirrus-CI build.  For more details, [see the automation
documentation](https://github.com/containers/automation/blob/main/cirrus-ci_artifacts/README.md).

## Build

This is a multi-stage build with some parallelism possible if stages were
previously cached.  For example:

`podman build -t ccia --jobs=4 .`

## Usage

It is recommended that you run the container with a `--workdir` set, and
a volume mounted at that location.  In this way, any downloaded
artifacts will be accessable after the container exits

Knowing a Cirrus-CI build ID, the container will download all artifacts (or select
[a subset using a
regex](https://github.com/containers/automation/tree/main/cirrus-ci_artifacts#usage).
The `--verbose` option shown below is not required.

```
BID=<Cirrus Build ID>
mkdir -p /tmp/artifacts
podman run -it --rm -v /tmp/artifacts:/data -w /data ccia $BID --verbose
ls -laR /tmp/artifacts
```
