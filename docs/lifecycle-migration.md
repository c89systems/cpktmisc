# cpktmisc lifecycle migration

This is a staged migration to `pkt-systems-cmake-lifecycle`. The prerequisite
and ownership foundation is implemented; the component build and delivery graph
still needs the cutover below before claiming full alignment.

## Preserved

Public `<cpkt/...>` headers, facade symbols and ABI majors, owned upstream pins
and patches, generators, facade behavior, test data, examples and license notices
are preserved. The seven SDK targets and static/shared consumer commitments remain.
`GROUP=all` means only cpktmisc. No operation builds or cleans a sibling provider.

## Implemented foundation

- Pin all seven published cpkt 0.1.0 SDKs by URL, archive SHA-256 and package ID.
  The baseline is [v0.1.0](https://github.com/c89systems/cpkt/releases/tag/v0.1.0),
  commit `95696cfb417f10430d09f0491eb982e29c89be07`. Downloaded archive hashes match
  its published CHECKSUMS; native validation checks each extracted SDK's manifest
  identity and complete declared payload. This establishes prerequisite identity;
  it does not establish cpktmisc consumer compatibility or runtime proof.
- Acquire, extract and validate core through Bash/CMake, with failure cleanup and
  validation before local SDK replacement. `make deps-core` bypasses the legacy
  operation broker. Core CMake imports use the native validator and imported
  versions come from the validated manifest.
- Vendor the installed skill's five provisioning/runtime helpers as one collection.
  Preserve the Bootlin, AFL++ and MIG pins; consolidate Linux toolchain discovery,
  propagate the helper directory and remove configure-time provisioning.
- Resolve shared caches under `${XDG_CACHE_HOME:-$HOME/.cache}/cpkt`, with `deps`
  and `toolchains` subdirectories. Full clean removes complete owned `build/`,
  `dist/` and `.cache/` trees, including hidden/control state.
- Use `make test-lifecycle` for native CTest foundation checks. Resolver fixtures
  now verify observable readiness, failures, runtime ownership and cleanup.
- Replace the hosted Darwin completion requirement with local release proof and
  optional diagnostics. The existing workflow has only `workflow_dispatch`.

## Remaining cutover before component proof

1. Remove `operation.sh`, `cpkt_lock.py`, build launch guards, arbitrary command
   interception and descriptor/process-broker machinery. Use the declared single
   workspace owner and caller-owned job cancellation contract.
2. Replace Python build/configure/receipt decisions and the verified-ExternalProject
   adapter with native CMake producer dependencies. Preserve effective-input reuse
   and missing/stale prerequisite failures without a receipt database.
3. Move Python test drivers and pipeline validation to small CMake/Bash or compiled
   CTest checks. Preserve permitted source/data generators and small data fixtures.
   Replace the legacy editor proof controller with native checks.
4. Migrate package staging, manifests, final-byte inspection, static/shared and
   relocated consumers, source reconstruction, memory checks and fuzz execution.
   Reuse the released core's small native patterns while retaining misc ownership,
   C++ runtime closure, facade exports and exact `requires_core` identities.
5. Replace reserved-tag recovery and hosted artifact handoff controllers. Enforce
   read-only final signed/lightweight-tag identity checks and one clean local final
   release. Hosted diagnostics cannot publish refs or supply release proof.
6. Prepare tools/core explicitly, then attempt the native cpktmisc build and product
   tests. Complete `make finalize-slice`, hardening and the applicable target/package
   gates after the native graph cutover. Do not describe foundation fixtures or
   core's release tests as passing cpktmisc build/runtime evidence.

The legacy component and delivery controllers still exist during this staged
migration. They are not endorsed by the new contract. No component build, release,
remote publication or sibling modification is part of the foundation evidence.
