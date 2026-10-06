# cpktmisc: OPC UA, PDF, audio and speech C89 SDK

[cpktmisc on GitHub](https://github.com/c89systems/cpktmisc) ships static and
shared libraries with strict C89 public interfaces, CMake packages, pkg-config
metadata, examples and complete third-party license notices.

## Delivered components

- libpng
- libharu
- miniaudio
- whisper
- open62541

Public headers keep the `<cpkt/...>` namespace and existing facade library names.
Shared-library ABI majors retain their existing identities. Repository release
versions are independent of those ABI majors.

## Independent repositories

| Repository | Scope | Prerequisite |
| --- | --- | --- |
| [cpkt](https://github.com/c89systems/cpkt) | Common libraries and cmocka | None |
| [cpktdb](https://github.com/c89systems/cpktdb) | PostgreSQL, SQLite and iODBC | Pinned cpkt SDK |
| [cpktmisc](https://github.com/c89systems/cpktmisc) | OPC UA, PDF, audio and speech | Pinned cpkt SDK |

Database and misc do not depend on each other. Only core maintains `skills/`.
Each producer owns its source, dependency recipes, tests, notices, artifacts and
release cycle. A database or misc change never starts a core producer or runs
core's standalone test suites.

## Development

Host Bash >= 4.4 is required for the lifecycle helpers. On macOS, run
`brew install bash`, then `export PATH="$(brew --prefix bash)/bin:$PATH"`
before Make or scripts. On Linux, install/upgrade the host `bash` package.
Run `bash scripts/require-host-bash.sh` to verify the selected shell.
See [host setup](docs/build-lifecycle.md) for the scope and PATH requirement.

Run `make help` for the authoritative command index. The default local Debug
preset uses the pinned Bootlin GNU toolchain. Every Linux target uses its own
complete pinned compiler collection. LLVM/Clang, clangd, clang-format, Valgrind
and QEMU are host tools; Darwin cross builds require osxcross and its Apple SDK.
The configured concurrency limit remains eight locally and two on native Darwin.

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

Before consumer operations, explicitly acquire the prerequisite:

```sh
make deps-core PRESET=debug
make debug
```

`dependencies/cpkt.json` pins one published core version and, for every supported
target, its exact GitHub URL, SHA-256 archive digest and portable package ID.
The initial 0.1.0 pins are populated from the verified core publication. Until
then acquisition fails clearly. There is no sibling-checkout or host-library
fallback. Ordinary consumer operations only validate an existing prerequisite;
`deps-core` is the explicit acquisition action.

An optional release need not have the same version as core. Its manifest records
the exact core release, target and package ID, and composition validates those
identities before importing libraries. Both extraction orders are verified.

## Distribution and release

All seven targets are retained: x86_64, aarch64 and armhf Linux with GNU and musl,
and arm64 Darwin. Each release ships:

- `cpktmisc-<version>-<target>.tar.gz` for each target;
- `cpktmisc-<version>-arm64-apple-darwin-smoke-test.zip`;
- `cpktmisc-<version>.tar.gz`, the independently reconstructed source archive;
- `cpktmisc-<version>-CHECKSUMS`, the exact upload inventory.

`make release` starts clean and runs the complete owning repository's required
gates. A candidate rehearsal cannot satisfy the tagged clean release. Native
macOS verification builds and tests the exact development commit in one GitHub
Actions run. Its archives are diagnostics only; release assets are built and
published locally, with Darwin built through osxcross on Linux. A separate
hosted check of local archive bytes is optional, not a release prerequisite.
Trunk and release tags are pushed only after the verified release boundary.

Shared dependency archives use
`${CPKT_DEPENDENCY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cpkt/deps}`;
compiler collections use the corresponding `cpkt/toolchains` root. A verified
SHA-256 cache hit performs no network acquisition. `clean` removes disposable
repository state and preserves both shared caches.

The native build ownership and specialist validation boundaries are documented in [build lifecycle architecture](docs/build-lifecycle.md).
