# cpktmisc: C89 SDK for archives, codecs, foreign calls, OPC UA, PDF and audio

[cpktmisc](https://github.com/c89systems/cpktmisc) ships static and
shared libraries with strict C89 public interfaces, CMake packages, pkg-config
metadata, examples and complete third-party license notices.

## Delivered components

- libpng
- libharu
- miniaudio
- whisper
- open62541
- libffi, libarchive, zstd and libyaml
- bzip2, xz/liblzma, LZ4 and LZO

libffi, libarchive, zstd, liblzma, LZ4 and LZO have complete C89 facade surfaces,
including advanced and deprecated public APIs. libyaml, bzip2 and libpng retain
their native C89 interfaces. PDF covers the complete libHaru API; audio and speech
retain their declared product APIs. See [facade contracts](docs/compression-facades.md)
and the [dependency inventory](docs/dependencies.md) for the current surface and
prerequisites. The [0.2.1 release notes](docs/releases/0.2.1.md) describe the
validation optimization and core upgrade. [0.2.0](docs/releases/0.2.0.md) records
the compatibility and metadata changes; [0.1.0](docs/releases/0.1.0.md) records
the original published inventory and consumer requirements.

Public headers keep the `<cpkt/...>` namespace and existing facade library names.
Shared-library ABI majors retain their existing identities. Repository release
versions are independent of those ABI majors.

`cpkt_audio` is a C89 facade over miniaudio. `cpkt_sus` is a C89 facade over a CPU-only whisper.cpp/ggml build.
NULL or empty cached-model name defaults to `tiny`. The `cpktxscribe` shell exposes the same
default and a `--cache-dir DIR` option. Model acquisition is explicit through the
cached-model constructor; the local-path constructor reads only the supplied file.
The default model directory is `${XDG_CACHE_HOME:-$HOME/.cache}/cpkt/susurro/models`.
Audio handles must be destroyed after use, including after encoder close. Speech
transcribers borrow their model and configuration strings; destroy transcribers
before the model and keep those strings valid until transcriber destruction.

## Independent repositories

| Repository | Scope | Prerequisite |
| --- | --- | --- |
| [cpkt](https://github.com/c89systems/cpkt) | Common libraries and cmocka | None |
| [cpktdb](https://github.com/c89systems/cpktdb) | PostgreSQL, SQLite and iODBC | Pinned cpkt SDK |
| [cpktmisc](https://github.com/c89systems/cpktmisc) | Archives, codecs, foreign calls, OPC UA, PDF, audio and speech | Pinned cpkt SDK |

Database and misc do not depend on each other. Only core maintains `skills/`.
Each producer owns its source, dependency recipes, tests, notices, artifacts and
release cycle. A database or misc change never starts a core producer or runs
core's standalone test suites.

## Development

Host Bash >= 4.4 is required for the lifecycle helpers. On macOS, run
`brew install bash`, then `export PATH="$(brew --prefix bash)/bin:$PATH"`
before Make or scripts. On Linux, install/upgrade the host `bash` package.
Run `bash scripts/require-host-bash.sh` to verify the selected shell.

Run `make help` for the authoritative command index. The default local Debug
preset uses the pinned Bootlin GNU toolchain. Every Linux target uses its own
complete pinned compiler collection. LLVM/Clang, clangd, clang-format, Valgrind
and QEMU are host tools; Darwin cross builds require osxcross and its Apple SDK.
The configured concurrency limit remains eight locally and two on native Darwin.

Make and Bash expose commands, CMake owns builds and installation, and CTest
runs checks. Ordinary `build` and `test` use native Debug; matrix commands select
the Release targets. Check lifecycle boundaries without compiling the product with:

```sh
make test-lifecycle
```

```sh
make debug
make finalize-slice
make test-all
```

`finalize-slice` formats project-owned C and headers, runs the Debug tests and
native clangd checks, then asserts formatting. `format-check` is required after
the final edit and before each commit. `test-all` includes the relevant native
hardening and integration tiers. Cross-target and extracted-package consumers
remain part of the complete release gate.

The clangd check publishes the native compilation database at
`build/compile_commands.json`; `.clangd` selects that directory. Public function
comments appear in editor hovers, including generated facade declarations and
their adaptations of upstream ownership and output contracts.

Before consumer operations, explicitly acquire the prerequisite:

```sh
make deps-core PRESET=debug
make debug
```

`dependencies/cpkt.json` pins one published core version and, for every supported
target, its exact GitHub URL, SHA-256 archive digest and portable package ID.
All seven 0.5.1 build pins come from the verified core publication. Native
CMake validates the selected SDK's manifest and payload bytes. There is no
sibling-checkout or host-library fallback. Ordinary consumer operations only validate an existing prerequisite;
`deps-core` is the explicit acquisition action.

An optional release need not have the same version as core. Its manifest records
the exact build prerequisite in `core_build_pin` and its consumer compatibility
baseline in `requires_core`. Installed misc packages require a core whose declared
compatibility span includes that baseline, with the same target; they independently
validate both SDKs' payloads. A newer compatible core can be selected without
rebuilding misc. Static applications relink to incorporate updated core code;
shared deployments select the new core libraries at runtime.
The current baseline is 0.5.1: the selected core must satisfy
`CpktCore_COMPATIBLE_SINCE <= 0.5.1 <= CpktCore_VERSION`.
Install core and misc into separate
prefixes and discover them through `CMAKE_PREFIX_PATH`, or their `lib/pkgconfig`
directories through `PKG_CONFIG_PATH`. Installed consumers use the selected core's
imported targets. Neither provider overlays or republishes
the other. Consumer tests relocate each SDK independently.
Core discovery uses the published `CpktCore` package and its validated prefix,
version, target, package ID and `CpktCore_COMPATIBLE_SINCE` floor.

For example, use `-DCMAKE_PREFIX_PATH="/opt/cpktmisc;/opt/cpkt"` with CMake,
or `PKG_CONFIG_PATH=/opt/cpktmisc/lib/pkgconfig:/opt/cpkt/lib/pkgconfig` with
pkg-config. The Darwin smoke ZIP contains misc libraries only; executing it also
requires a compatible core installation on the runtime library search path.
pkg-config version constraints cannot check the compatibility floor or payload
integrity. Before linking through pkg-config, run the installed validator using
the same pkg-config executable and environment as the subsequent link query:

```sh
export PKG_CONFIG_PATH=/opt/cpktmisc/lib/pkgconfig:/opt/cpkt/lib/pkgconfig
cmake -S /opt/cpktmisc/lib/cmake/CpktMisc/pkg-config \
  -B build/cpkt-pkg-config-validation \
  -DCPKT_SDK_PREFIX=/opt/cpktmisc -DPKG_CONFIG_EXECUTABLE="$(command -v pkg-config)"
```

Use a fresh validation build directory when changing SDK selections. This checks
that CMake validates the core selected by pkg-config, including its floor, target
and payload. The shipped `build-pkg-config.sh` examples perform this validation
in a fresh temporary directory before invoking the compiler.
For cross builds, append both SDK prefixes to `CMAKE_FIND_ROOT_PATH` in the
consumer's CMake setup and retain `CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY`.

## Distribution and release

All seven targets are retained: x86_64, aarch64 and armhf Linux with GNU and musl,
and arm64 Darwin. Each release ships:

- `cpktmisc-<version>-<target>.tar.gz` for each target;
- `cpktmisc-<version>-arm64-apple-darwin-smoke-test.zip`;
- `cpktmisc-<version>.tar.gz`, the independently reconstructed source archive;
- `cpktmisc-<version>-CHECKSUMS`, the exact upload inventory.

Use `make prerelease` for incremental candidate checks. `make release` requires
a clean signed commit and its exact lightweight release tag, then starts clean
and verifies the final artifacts. Push trunk and the tag only after that gate
passes. Darwin uses local osxcross; hosted checks are optional diagnostics.

Shared dependency archives use
`${CPKT_DEPENDENCY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cpkt/deps}`;
compiler collections use the corresponding `cpkt/toolchains` root. A verified
SHA-256 cache hit performs no network acquisition. `clean` removes disposable
repository state and preserves both shared caches.
