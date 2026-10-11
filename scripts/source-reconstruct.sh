#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lifecycle-common.sh"
export GROUP=all CPKT_SOURCE_RECONSTRUCTION=1
case "${1:-}" in ''|release) ;; *) cpkt_fail 'usage: source-reconstruct.sh [release]' ;; esac
if [ "${1:-}" = release ]; then
  [ ! -e "$cpkt_root/.cache" ] || cpkt_fail 'final source reconstruction starts from clean compiled state'
  export CPKT_RELEASE_PRODUCTION=1
fi
bash "$cpkt_scripts/core-dependency.sh" --target x86_64-linux-gnu
bash "$cpkt_scripts/build.sh" test --group misc --preset x86_64-linux-gnu-release
bash "$cpkt_scripts/package.sh" package-stage --group misc --preset x86_64-linux-gnu-release --scope selected
bash "$cpkt_scripts/package.sh" package-checksums --group misc --preset x86_64-linux-gnu-release --scope selected
bash "$cpkt_scripts/package.sh" package-verify --group misc --preset x86_64-linux-gnu-release --scope selected
