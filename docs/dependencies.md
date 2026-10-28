# cpktmisc dependencies

## Shipped libraries

- libpng (pinned recipe and license: `cmake/components.json`).
- libharu (pinned recipe and license: `cmake/components.json`).
- miniaudio (pinned recipe and license: `cmake/components.json`).
- whisper (pinned recipe and license: `cmake/components.json`).
- open62541 (pinned recipe and license: `cmake/components.json`).
- libffi, libarchive, zstd and libyaml (pins and licenses: `cmake/components.json`).
- bzip2, xz/liblzma and LZ4 for libarchive's enabled bundled codecs.

Libarchive supports gzip through core's zlib. LZO is not bundled or linked;
libarchive's LZO backend is disabled.

The C89 facade boundaries, target-specific public records, streaming behavior
and license locations are described in [compression-facades.md](compression-facades.md).

## Prerequisites and test tooling

Core comes exclusively from checksum-pinned `c89systems/cpkt` release artifacts. The exact pins are in `dependencies/cpkt.json`. Core is not repackaged.

The build uses pinned core 0.6.1, whose compatibility floor remains 0.2.0.
Installed misc SDKs record that exact provenance separately from their core
compatibility baseline, which is 0.6.1 for new builds. Downstream may select a newer
core when its declared compatibility span includes the baseline and its target
matches; CMake independently validates the selected core payload. pkg-config
consumers must use the installed validator before linking so both discovery
paths select the same core; see the [consumer instructions](../README.md).

`libpslog` is a pinned test-only logging consumer and is not shipped or linked into production facades. CMake, Ninja/Make, Python and host development tools are build/test requirements. Upstream archives, patch series and enabled static/shared features are recorded by the component inventory and recipe. Artifact-local notices accompany each delivered component.
