# Native lifecycle cutover

cpktmisc uses the installed `pkt-systems-cmake-lifecycle` contract. Make publishes
commands, Bash preserves arguments and foreground sequencing, CMake owns the
producer/install graph, and CTest owns tests and assertions. One mutable checkout
belongs to one operation; the terminal/job runner cancels the entire job group.

The former operation broker, descriptor delegation, compile/command interception,
Python receipts, per-case fixture evidence, reserved-tag recovery and hosted
artifact handoff are removed. Their controller-specific tests are replaced by
native checks of acquisition, ownership, cleanup, dependency invalidation, suite
reuse, release identity, archives, installed consumers and source reconstruction.

## Preserved product boundary

Public `<cpkt/...>` headers, facade symbols and ABI majors, upstream pins and
patches, generators, facade behavior, test data, examples and licenses remain.
The seven SDK targets and static/shared consumer commitments are preserved.
`GROUP=all` means only cpktmisc; cpktdb is independent. Core is a published SDK
prerequisite, never another checkout or a core producer.

All seven prerequisite pins identify [cpkt v0.1.0](https://github.com/c89systems/cpkt/releases/tag/v0.1.0),
commit `95696cfb417f10430d09f0491eb982e29c89be07`, by release URL, archive SHA-256,
and package ID. Downloaded archives match the published CHECKSUMS; native CMake
checks manifest identity and declared payload bytes. Imported component versions
come from that manifest. Optional package version and ABI majors remain independent
of core's release version; schema markers are unchanged.

## Native implementation

- Five vendored lifecycle provisioning/runtime helpers match the installed skill.
  Linux configure and compiler probes discover prepared Bootlin tools; only an
  explicit ensure provisions. Native Darwin uses Apple tools and Linux-host Darwin
  uses prepared osxcross plus the pinned host MIG collection.
- Global caches use `${XDG_CACHE_HOME:-$HOME/.cache}/cpkt`, with separate `deps`
  and `toolchains` namespaces. Full clean removes entire owned `build/`, `dist/`
  and `.cache/` trees, including hidden entries. Another checkout's generated
  tools, sources, caches and outputs cannot be borrowed.
- Native ExternalProject edges and component input/completion files preserve
  dependency reuse. CMake suite-scoped success outputs are created only after
  complete CTest success. Tests changed independently of libraries do not rebuild
  unchanged producers. Restored state with preserved timestamps requires explicit
  invalidation; inputs and tools remain stable during an operation.
- Python is limited to source/data generators and small audio/archive-origin
  fixtures. Generated API inventory and SDK manifests are data; native drivers
  own their assertions. Public header contracts use a compiled C89 scanner.
- CMake install stages only owned misc payload, metadata and notices. Native
  final-byte checks verify inventory, versions, hashes, architecture, facade ABI,
  exports/imports, privacy and relocatability. Composition checks exact core
  identity and unique path ownership in both extraction orders. Installed CMake
  and pkg-config consumers include C89, shared/static, PIC, mixed C++ and examples.
- Darwin libpng explicitly uses the flat dylib layout required by the SDK metadata.
  Its upstream ABI identity is retained. Linux speech includes the selected
  separate GNU runtime archives and notices; Darwin uses its system libc++ closure.
- Release identity checks are read-only. Final release requires a clean signed
  commit and exact lightweight tag before cleaning or producing artifacts; a
  failure stops. Hosted native diagnostics are manual opt-in on an existing remote
  ref, never release gates/artifacts or a reason to push.

## Verification scope

The cutover is checked through native lifecycle fixtures, Debug and Release CTest
scopes, clangd/comment checks, Valgrind and AFL++ smoke, final archives and
installed/relocated consumers, Darwin Mach-O inspection and link proof, and clean
source reconstruction. Exact results are reported with the completed change.
Darwin runtime remains deferred on a Linux host. Live speech/model checks require
explicit opt-in; default required suites cannot count an opt-out as a pass.
