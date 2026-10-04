# cpktmisc dependencies

## Shipped libraries

- libpng (pinned recipe and license: `cmake/components.json`).
- libharu (pinned recipe and license: `cmake/components.json`).
- miniaudio (pinned recipe and license: `cmake/components.json`).
- whisper (pinned recipe and license: `cmake/components.json`).
- open62541 (pinned recipe and license: `cmake/components.json`).

## Prerequisites and test tooling

Core comes exclusively from checksum-pinned `c89systems/cpkt` release artifacts. The exact pins are in `dependencies/cpkt.json`. Core is not repackaged.

`libpslog` is a pinned test-only logging consumer and is not shipped or linked into production facades. CMake, Ninja/Make, Python and host development tools are build/test requirements. Upstream archives, patch series and enabled static/shared features are recorded by the component inventory and recipe. Artifact-local notices accompany each delivered component.
