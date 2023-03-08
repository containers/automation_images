# Bench Stuff

This container facilitates stuffing podman CI benchmarks into GCE firebase.
For more details, [see the automation
documentation](https://github.com/containers/automation/blob/main/bench_stuff/README.md).

## Build

This is a multi-stage build with some parallelism possible if stages were
previously cached.  For example:

`podman build -t bench_stuff --jobs=4 .`

## Usage

1. Utilize [the ccia container image](https://quay.io/repository/libpod/ccia) to retrieve
   benchmark data from a podman Cirrus-CI build into a temporary directory.
   ```
   $ mkdir /tmp/b
   $ podman run -it --rm \
       -v /tmp/b:/b:Z -w /b \
       quay.io/libpod/ccia 1234567890 'benchmark/data'
   ```
1. Run the `bench_stuff` container, providing it with proper credentials, and a reference
   to the temporary directory (containing the benchmark data).
   ```
   $ podman secret create GAC $GOOGLE_APPLICATION_CREDENTIALS
   $ podman run -it --rm -v /tmp/b:/b:Z,ro \
       --secret GAC -e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/GAC
       quay.io/libpod/ccia /b
   ```
