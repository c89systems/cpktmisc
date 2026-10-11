#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lifecycle-common.sh"
[ "$cpkt_owner" = misc ] || cpkt_fail 'this prerequisite belongs to cpktmisc'
cpkt_check_group "${GROUP:-all}"
case "${1:-}" in
  --preset)
    [ "$#" = 2 ] || cpkt_fail 'usage: core-dependency.sh --preset <preset> | --target <target>'
    cpkt_preset "$2"
    target=$cpkt_target ;;
  --target)
    [ "$#" = 2 ] || cpkt_fail 'usage: core-dependency.sh --preset <preset> | --target <target>'
    target=$2 ;;
  *) cpkt_fail 'usage: core-dependency.sh --preset <preset> | --target <target>' ;;
esac
case "$target" in x86_64-linux-gnu|x86_64-linux-musl|aarch64-linux-gnu|aarch64-linux-musl|armhf-linux-gnu|armhf-linux-musl|arm64-apple-darwin) ;;
  *) cpkt_fail "unsupported imported core target: $target" ;;
esac
cpkt_check_cache_overrides
workspace="$cpkt_root/build/core-acquisition/$target"
destination="$cpkt_root/.cache/cpkt/$target/install"
cpkt_owned_path "$workspace/archive-path"
cpkt_owned_path "$destination"
run_core() {
  "$cpkt_cmake" "-DCPKT_REPO_ROOT=$cpkt_root" "-DCPKT_CORE_TARGET=$target" \
    "-DCPKT_CORE_ACTION=$1" "${@:2}" -P "$cpkt_root/cmake/core-dependency.cmake"
}
# Valid installed bytes need no archive acquisition. Only this explicit command
# repairs a damaged local extraction.
if [ -f "$destination/share/cpkt/packages/core.json" ]; then
  if run_core validate; then run_core link; exit 0; fi
fi
mkdir -p "$workspace"
run_core acquire
stage=$(mktemp -d "$workspace/extract.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
run_core extract "-DCPKT_CORE_STAGE=$stage"
# Failed download, extraction or validation leaves the existing SDK intact.
mkdir -p "$(dirname -- "$destination")"
rm -rf -- "$destination"
mv -- "$stage/sdk" "$destination"
run_core link
printf 'cpktmisc: verified core SDK ready for %s\n' "$target"
