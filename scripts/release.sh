#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lifecycle-common.sh"
action=${1:?release action required}
[ "${GROUP:-all}" = all ] || cpkt_fail 'release workflows require GROUP=all'
export GROUP=all
prepare_core_targets() {
  while IFS= read -r target; do
    bash "$cpkt_scripts/cpkt-toolchains.sh" ensure "$target"
    bash "$cpkt_scripts/core-dependency.sh" --target "$target"
  done < <(cpkt_info targets)
}
run() {
  bash "$cpkt_scripts/lifecycle.sh" "$1" --group all --preset debug --preset-explicit no \
    --scope '' --scope-explicit no --dependency ''
}
case "$action" in
  prerelease) exec bash "$0" release-pipeline ;;
  prerelease-hardening)
    run prerelease
    run fuzz
    exit 0 ;;
  release-final-matrix) exec bash "$0" release ;;
  release-matrix)
    prepare_core_targets
    bash "$cpkt_scripts/package.sh" package --group all --scope binary
    scope=binary
    bash "$cpkt_scripts/package.sh" package-checksums --group all --scope "$scope"
    bash "$cpkt_scripts/package.sh" package-verify --group all --scope "$scope"
    exit 0 ;;
  release|release-pipeline|test-all) ;;
  *) cpkt_fail "unsupported release action: $action" ;;
esac
if [ "$action" = release ]; then
  export CPKT_RELEASE_PRODUCTION=1
  run lifecycle-version-contract
  run clean
  run format-check
  run package-source
fi
if [ "$action" != test-all ] && [ "$action" != release ]; then
  if [ "${CPKT_RELEASE_PRODUCTION:-0}" != 1 ]; then run format; fi
  run format-check
fi
bash "$cpkt_scripts/cpkt-aflpp.sh" ensure
if [ "$action" = test-all ]; then
  bash "$cpkt_scripts/core-dependency.sh" --target x86_64-linux-gnu
else
  prepare_core_targets
fi
if [ "$action" = release ]; then
  version=$(bash "$cpkt_scripts/release-version.sh" "$cpkt_root")
  bash "$cpkt_scripts/source-archive-verify.sh" \
    "$cpkt_root/dist/$cpkt_provider-$version.tar.gz" "$version" --release-build
fi
run debug
run clangd-surface
run valgrind
run fuzz-smoke
case "$action" in
  release)
    # Clean source reconstruction supplies native Release. Cross lanes retain
    # their own checkout-local producers; none borrow the extracted build state.
    while IFS= read -r target; do
      [ "$target" != x86_64-linux-gnu ] || continue
      bash "$cpkt_scripts/package.sh" package --group misc --preset "$target-release" --scope selected
      cp -- "$cpkt_root/build/package-stage/$target/misc/archives/$cpkt_provider-$version-$target.tar.gz" "$cpkt_root/dist/"
    done < <(cpkt_info targets)
    cpkt_preset arm64-apple-darwin-release
    "$cpkt_cmake" --build "$cpkt_binary" --parallel "$(cpkt_jobs "$cpkt_binary")" --target package-darwin-smoke
    bash "$cpkt_scripts/package.sh" package-checksums --group all --scope release
    bash "$cpkt_scripts/package.sh" package-verify --group all --scope release ;;
  release-pipeline) run release-matrix ;;
esac
