# Native lifecycle architecture

The lifecycle helpers require host **Bash 4.4 or newer** for nounset-safe empty
arrays, dynamic file descriptors and `mapfile`. This host prerequisite does not
apply to unrelated consumers of the C89 SDK. Helpers reject an unsupported
shell before lifecycle discovery, cache work or native children.

On macOS, install Homebrew Bash and give it PATH precedence in the terminal
that runs Make and scripts (the system `/bin/bash` remains unchanged):

```sh
brew install bash
export PATH="$(brew --prefix bash)/bin:$PATH"
bash scripts/require-host-bash.sh
```

On Linux, include `bash` in the host package baseline (for example
`sudo apt-get install bash`), upgrading it if older than 4.4. The command above
prints the actual selected shell version and path. Installing a formula alone
does not select it; Make, operations and compiler/native launchers must inherit
that PATH. Bash is a host tool, never a cpkt SDK or toolchain cache product.

Make exposes public names and short recipes. `scripts/lifecycle.sh` validates
selectors and routes to readable Bash workflows. `make help` is the command
index. `scripts/build.sh configure|build|test|deps|path|preflight` is the native
build surface. `scripts/operation.sh --group <owner|all> -- <command>` supplies
repository ownership; it never widens scope to a sibling checkout.

CMake evaluates presets, selects tools, owns ExternalProject dependency edges,
component contracts, incremental builds, CTest registration and required
coverage. `CpktABIVersions.cmake` owns facade ABI declarations. Bash sequences
producer preparation and consumer configuration; it retains cached job limits,
with Linux maximum 8 and native Darwin maximum 2. Hardening borrows verified
ordinary Debug output. Missing/stale borrowed inputs fail with preparation
commands. Ordinary work does not clean shared archives or toolchain caches.
Before accepting a saved contract, native CMake checks its recorded recipe,
file, inventory and transitive dependency inputs against current source bytes.
This read-only check also protects hardening that borrows ordinary Debug output;
it never configures a producer or rebuilds a dependency.
Verified warm ExternalProject nodes retain their dependency edges and validate
original receipts on every native build. Changed launcher/stamp scripts never
replay a compiled install. Recipe/input or output corruption selects the full
native producer path. Verified warm nodes skip source-archive acquisition,
including when the archive cache and seed locations are empty. The
native adapter's actual bytes are part of that contract.

CMake install rules stage owned SDK payload, public generated headers, discovery
metadata, example sources and complete licenses. `scripts/archive.sh` uses GNU
tar and gzip with fixed timestamps/order/ownership and compression level 6.
Both SDK and source packaging use that writer, including generated version/manifest
files and staging directories; unchanged source bytes reproduce across checkout timestamps.
Source staging uses umask 022 for generated files/directories and preserves copied input modes.
Manifests retain content, modes, symlinks, versions, source hashes, facade features,
ABI/loader identities and exact optional-core requirements. Optional providers
use their own archive roots and versions and require a published checksum pin;
empty target pins remain intentional until publication.
Optional recipes use the single validated `CPKT_CORE_PREFIX` for every imported
library. Complete release workflows restore their exact target SDK prerequisites
after clean; source reconstruction and both Darwin proofs prepare their own
prerequisite explicitly before consumer work. Ordinary selected builds still
require prior `deps-core` preparation. Explicit acquisition verifies/restores the
archive even when the installed SDK can be reused, without replacing valid bytes.

Bash owns flock, stable lock inodes, nested operations, process groups, bounded
signal cleanup and command diagnostics. Persistent service execution closes the issued descriptor numbers, including recovered handles, and clears operation capabilities before exec. `scripts/package-command.sh` applies
that process policy to validator-owned external tool probes too. The Python
output adapter forwards signals to this Bash owner and reads its output. It bounds
capture draining after the owner exits: detached writers cannot keep the operation
open, and incomplete successful captures cannot supply verification evidence.
It does not manage groups or schedule builds. Fixture reuse requires the same live run,
exact input bytes/environment, command argv and output identities. Completed
readiness requires every native required CTest case exactly once in successful
JUnit; filtered or failed runs cannot publish full readiness.
Readiness binds the current CMake graph and preset source bytes as well as the
configured outputs. Release verification aliases always select complete release
scope, including source artifacts and reconstruction evidence.

Source reconstruction uses `scripts/source-reconstruct.sh` in an independently
locked extracted source root with the parent's actual shared cache, generator and
lower job limit. Source and native Darwin proofs record actual executions, never
invented readiness. Release remains a separate final workflow; implementation
fixtures must use throwaway repositories for Git ref interruption/recovery.

## Python exceptions

The following are specialist tasks, not build controllers. Each helper has a
specific reason; JSON alone is insufficient. No Python preset interpreter,
lifecycle dispatcher or dependency scheduler is retained.

- **POSIX descriptor authentication** — `scripts/cpkt_lock.py`: Bash flock handles are intentionally closed by CMake/CTest. fstat, pread, access-mode inspection and authenticated SCM_RIGHTS transfer reissue the exact live descriptions, including long socket paths; Bash owns locking, process groups, waiting and cleanup.

- **SDK/archive/binary structure** — `scripts/validate-sdk.py`, `scripts/cpkt_packages.py`, `scripts/cpkt_archive_assert.py`, `scripts/cpkt_archive_extract.py`, `scripts/cpkt_package_manifest.py`, `scripts/cpkt_verify_manifest.py`, `scripts/cpkt_darwin.py`: Canonical manifests, duplicate-key rejection, safe archive member/symlink preflight, ELF/Mach-O load identities, exact composition requirements, archive privacy and deterministic ZIP modes need one structured validation implementation. These helpers validate bytes and evidence; native install rules and GNU tar own SDK staging and tar creation.

- **Content and test evidence** — `scripts/cpkt_inventory.py`, `scripts/cpkt_receipts.py`, `scripts/cpkt_receipt_cli.py`, `scripts/cpkt_configure_guard.py`, `scripts/cpkt_build_evidence.py`, `scripts/cpkt_memcheck_evidence.py`, `scripts/cpkt_fixture_identity.py`, `scripts/cpkt_helper_proof.py`, `scripts/cpkt_source_proof.py`: Content/mode/symlink closures, canonical atomic receipts, CTest JSON and JUnit/Memcheck XML are compared structurally. These validators neither select build order nor interpret presets. CMake computes component contracts and required coverage; Bash executes commands. The inline checks in `scripts/source-archive-verify.sh` validate the reconstructed inventory and canonical source manifest against extracted files before building; they perform no lifecycle dispatch.

- **Installed consumer specification** — `scripts/cpkt_sdk_consumer.py`, `scripts/cpkt_sdk_examples.py`: Generate independent downstream CMake graphs and validate exact static/shared/PIC closures, pkg-config argv and loader evidence against manifest geometry. CMake owns compilation and target dependencies. Python collects structured executable/ABI evidence; package-command.sh owns process groups and cancellation.

- **Native configuration adapters** — `scripts/cpkt_presets.py`, `scripts/configured_build.py`, `scripts/cpkt_darwin_tools.py`: Specialist validators need configured paths and tools. These small adapters bind a typed configured tool map to the ELF/Mach-O and consumer validators, check cold facade ABI defaults through native CMake, and reject host fallback or mismatched target tools; no preset inheritance, scheduling or lifecycle dispatch exists here.

- **Editor validation and compiler dependencies** — `scripts/cpkt_clangd_check.py` and the inline validator in `scripts/verify-clangd-surface.sh`: Parse compiler Make dependency escaping and JSON compile commands to bind the actual transitive header/tool byte closure, then atomically publish the editor database and same-run proof. The inline validator parses C declarations, definitions and adjacent Doxygen comments; clangd checks use the actual compiler input closure. Bash performs editor commands.

- **Database API inventory** — `scripts/db_api_inventory.py`: Compare enabled public C declarations and binding decisions using parsed syntax; shell token substitution cannot distinguish declarations, ownership and signatures reliably.

- **Remote and Git evidence** — `scripts/cpkt_github_handoff.py`, `scripts/cpkt_reserved_tag.py`: Validate authenticated GitHub JSON, official redirect/credential boundaries, checksum cache identities or owned ref recovery records. Bash version-contract.sh performs Git ref creation/deletion. This refactor does not invoke remote publication or tag mutation.

- **Selected executable preflight** — `scripts/run-selected-tests.py`: Read CTest JSON and reject absent/non-executable command arrays before any selected case executes; shell text parsing cannot safely preserve arbitrary JSON argv. CTest owns test execution.

**Published core validation** — `scripts/cpkt_core.py` validates exact pin schemas, canonical SDK manifests, archive identities and imported component records. Duplicate-key, checksum, content/mode and composition validation need structured data; Bash/CMake own acquisition and extraction sequencing.

**Facade generation** — These tools operate on parsed C declarations and upstream type graphs, requiring structured type, callback and ownership transformations. CMake owns their generation edges; they never schedule dependency builds. `tools/generate_pdf_facade.py` translates libHaru declarations and ownership documentation into the maintained C89 facade. The OPC UA specialists are:

- `tools/opcua/async_client_emitter.py`: Bind the complete public async client header without rebuilding services.
- `tools/opcua/c89_emitter.py`: C89 backend for open62541's parsed public type graph (no schema parser).
- `tools/opcua/certificate_emitter.py`: Certificate and trust-list boundaries derived from public declarations.
- `tools/opcua/client_emitter.py`: Generate the entire synchronous public high-level client header.
- `tools/opcua/codec_emitter.py`: C89 public codec records and bindings, derived from upstream declarations.
- `tools/opcua/config_emitter.py`: Derive configuration values and stock helpers from public declarations.
- `tools/opcua/config_plugin_emitter.py`: Bind configuration-owned native security plugins without cloning backends.
- `tools/opcua/config_server_plugin_emitter.py`: Callable views of native server plugins; never clone their private contexts.
- `tools/opcua/core_client_emitter.py`: Bind client lifecycle/discovery/session operations from public declarations.
- `tools/opcua/creation_emitter.py`: Generate node creation calls from the public server declarations.
- `tools/opcua/dynamic_emitter.py`: Derive public descriptor kinds; expose descriptor ownership and introspection.
- `tools/opcua/event_emitter.py`: Derive event descriptions and local notification signatures from server.h.
- `tools/opcua/eventloop_emitter.py`: Expose native event-loop methods without copying architecture-private state.
- `tools/opcua/format_emitter.py`: Retain upstream formatting; adapt argument reads at the C89 ABI boundary.
- `tools/opcua/generate.py`: Apply the maintained emitter hook to a disposable copy of upstream tools.
- `tools/opcua/header_contract.py`: Check public C89 header tokens without rejecting documentation or literals.
- `tools/opcua/history_emitter.py`: Derive history backend callbacks from authoritative public native headers.
- `tools/opcua/node_emitter.py`: Generate usable public node callbacks from native handwritten declarations.
- `tools/opcua/nodestore_emitter.py`: Expose the public nodestore methods over actual opaque native storage.
- `tools/opcua/plugin_emitter.py`: Generate callback records and trampolines from handwritten public plugins.
- `tools/opcua/policy_emitter.py`: Generate complete public policy callback bridges and stock constructors.
- `tools/opcua/producer_emitter.py`: Derive public producer callback declarations from installed native headers.
- `tools/opcua/public_api.py`: Inventory the enabled public SDK declarations with the configured compiler.
- `tools/opcua/pubsub_emitter.py`: Derive full PubSub records and boundary conversions from public headers.
- `tools/opcua/security_emitter.py`: Public certificate-group callbacks and native factories.
- `tools/opcua/server_emitter.py`: Generate schema-only server boundaries from authoritative public declarations.
- `tools/opcua/utility_emitter.py`: Public common records and schema utilities derived from upstream headers.
- `tools/opcua/value_emitter.py`: Native public value factories, preserving borrowed and allocated storage.

Each emitter consumes the authoritative public declaration/type graph and emits its specific C89 boundary records, callbacks or conversions. Python is necessary for that structural representation; native upstream runtime behavior remains upstream-owned.

Python tests construct isolated adversarial archive, metadata, compiler and POSIX fixtures and assert observable behavior; they do not drive production builds.
