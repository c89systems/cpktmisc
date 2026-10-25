# cpktmisc dependencies

## Shipped libraries

- libpng (pinned recipe and license: `cmake/components.json`).
- libharu (pinned recipe and license: `cmake/components.json`).
- miniaudio (pinned recipe and license: `cmake/components.json`).
- whisper (pinned recipe and license: `cmake/components.json`).
- open62541 (pinned recipe and license: `cmake/components.json`).
- libffi, libarchive, zstd and libyaml (pins and licenses: `cmake/components.json`).
- bzip2, xz/liblzma, LZ4 and LZO, including libarchive's complete bundled codec closure.

The C89 facade boundaries, target-specific public records, streaming behavior
and license locations are described in [compression-facades.md](compression-facades.md).

## Prerequisites and test tooling

Core comes exclusively from checksum-pinned `c89systems/cpkt` release artifacts. The exact pins are in `dependencies/cpkt.json`. Core is not repackaged.

The build uses pinned core 0.5.1. Installed misc SDKs record that exact provenance
separately from their core compatibility baseline. Downstream may select a newer
core when its declared compatibility span includes the baseline and its target
matches; CMake independently validates the selected core payload. pkg-config
consumers must use the installed validator before linking so both discovery
paths select the same core; see the [consumer instructions](../README.md).

`libpslog` is a pinned test-only logging consumer and is not shipped or linked into production facades. CMake, Ninja/Make, Python and host development tools are build/test requirements. Upstream archives, patch series and enabled static/shared features are recorded by the component inventory and recipe. Artifact-local notices accompany each delivered component.
