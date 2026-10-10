# Native lifecycle contract

cpktmisc is adopting the installed `pkt-systems-cmake-lifecycle` skill. The
migration status and remaining work are in [the migration ledger](lifecycle-migration.md).
The product remains the OPC UA, PDF, audio and speech C89 SDK; core is an exact
published prerequisite and cpktdb is independent.

Make owns public commands, Bash owns arguments and foreground sequencing,
CMake owns configure/dependency/build/install edges, and CTest owns test execution
and assertions. One operation owns each mutable checkout. Keep inputs and tools
stable during checks; the terminal or job runner cancels the entire job/process
group. No process broker, per-case receipt service or competing scheduler belongs
in this lifecycle.

Host Bash 4.4 or newer is required. On macOS, install Homebrew Bash and give its
bin directory PATH precedence; on Linux, use the workstation Bash package.
`bash scripts/require-host-bash.sh` checks the actual selected shell. CMake,
Make/Ninja, Git, archive/hash/download tools and test tools are workstation
prerequisites. LLVM/Clang remains workstation-managed.

The declared vendored lifecycle helpers live together in `scripts/`:
`require-host-bash.sh`, `cpkt-archive-cache.sh`, `cpkt-toolchains.sh`,
`cpkt-aflpp.sh` and `cpkt-afl-runtime.sh`. They are copied from the installed
skill, whose authoritative source belongs to cpkt. CMake resolves
`CPKT_LIFECYCLE_SCRIPTS_DIR` to this location and propagates it into compiler
probes. Toolchain configure/discover/env never provision; only an explicit
`ensure` prepares the pinned collections. Linux uses the six Bootlin 2026.08-1
collections, native macOS uses Apple tools, and Linux-host Darwin builds use
operator-prepared osxcross and the pinned host MIG helper. Missing tools fail.
Configured job limits remain eight on Linux and two on native Darwin.

Shared verified dependency archives use
`${CPKT_DEPENDENCY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cpkt/deps}`.
Tool collections use
`${CPKT_TOOLCHAIN_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cpkt/toolchains}`.
There is no `c.pkt.systems` cache fallback or automatic cache migration.
Repo-local `.cache/` contains disposable extraction/build/install state;
`build/` contains graphs, fixtures and diagnostics, and `dist/` contains final
artifacts. Full clean removes all three complete directories, including hidden
entries. Checkouts never borrow another checkout's generated tools or state.

`make deps-core PRESET=<preset>` explicitly acquires the SDK selected by
`dependencies/cpkt.json`. The seven target pins contain the exact cpkt 0.1.0
archive URL, SHA-256 and portable package ID. Native CMake validates the manifest,
platform identity, payload hashes, modes and links. It validates archive members
before extraction and validates staged bytes before replacing the local SDK.
A valid installed SDK is reused without archive acquisition; an archive hit is
rehashed and makes no acquisition requests. Ordinary consumer operations only
validate their existing prerequisite and report `make deps-core` when it is absent
or damaged. No sibling checkout, core producer or host library can supply it.
Imported component versions come from the verified core manifest.

`make test-lifecycle` runs native prerequisite, cache, cleanup, archive and resolver
fixtures without compiling cpktmisc. Product builds, facade tests, clangd,
Valgrind, fuzzing and final installed/relocated consumers remain required in their
applicable scopes as the remaining graph is migrated. Source/data generators and
small data fixtures may use Python. Python test drivers and lifecycle controllers
are migration debt, not permitted exceptions.

Preparation is incremental. Final release requires a clean committed checkout,
a verified signature on the final amended commit and its exact lightweight tag
before clean/build. A failed final release stops. Only the complete local gate
and final shipped-byte checks authorize release publication. Darwin release proof
uses local osxcross; hosted native checks are optional diagnostics dispatched on
an existing remote ref. Never push to obtain CI feedback. Source, artifact and
release versions remain independent of shared-library ABI majors.
