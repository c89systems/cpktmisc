#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lifecycle-common.sh"
archive=${1:?archive required}
target=${2:?target required}
version=${3:?version required}
smoke=${4:-}
[ -f "$archive" ] || cpkt_fail "SDK archive is missing: $archive"
archive="$(CDPATH= cd -- "$(dirname -- "$archive")" && pwd -P)/${archive##*/}"
if [ -n "$smoke" ]; then
  [ -f "$smoke" ] || cpkt_fail "Darwin smoke archive is missing: $smoke"
  smoke="$(CDPATH= cd -- "$(dirname -- "$smoke")" && pwd -P)/${smoke##*/}"
fi
cpkt_preset "$target-release"
if [ "$target" = arm64-apple-darwin ] && [ "$(uname -s)" = Darwin ]; then
  tool=$(xcrun --find otool)
else
  report=$(bash "$cpkt_scripts/cpkt-toolchains.sh" discover "$target")
  if [ "$target" = arm64-apple-darwin ]; then
    tool=$(sed -n 's/^otool=//p' <<< "$report")
  else
    tool=$(sed -n 's/^readelf=//p' <<< "$report")
  fi
fi
[ -x "$tool" ] || cpkt_fail "Missing target inspection tool for $target"
workspace="$cpkt_root/build/package-verify/$target"
nm_tool=
ar_tool=
if [ "$target" = arm64-apple-darwin ] && [ "$(uname -s)" = Darwin ]; then
  nm_tool=$(xcrun --find nm)
  ar_tool=$(xcrun --find ar)
else
  nm_tool=$(sed -n 's/^nm=//p' <<< "$report")
  ar_tool=$(sed -n 's/^ar=//p' <<< "$report")
fi
cpkt_owned_path "$workspace"
"$cpkt_cmake" -S "$cpkt_root/tests/package" -B "$workspace" -G Ninja \
  "-DCPKT_SOURCE=$cpkt_root" "-DCPKT_ARCHIVE=$archive" "-DCPKT_TARGET=$target" \
  "-DCPKT_VERSION=$version" "-DCPKT_TOOL=$tool" "-DCPKT_NM=$nm_tool" "-DCPKT_AR=$ar_tool" "-DCPKT_SMOKE_ARCHIVE=$smoke"
"$cpkt_cmake" --build "$workspace" --target verify_package
