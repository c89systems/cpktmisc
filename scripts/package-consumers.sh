#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lifecycle-common.sh"
prefix=${1:?SDK prefix required}
target=${2:?target required}
workspace=${3:?consumer workspace required}
cpkt_owned_path "$workspace"
cpkt_preset "$target-release"
cpkt_require_core
core="$cpkt_root/.cache/cpkt/$target/install"
unset SASL_PATH
arguments=(-G 'Unix Makefiles' "-DCPKT_SOURCE=$cpkt_root" "-DCPKT_TARGET_ID=$target")
can_run=ON
case "$target" in
  *-linux-*) arguments+=("-DCMAKE_TOOLCHAIN_FILE=$cpkt_root/cmake/CpktReadOnlyToolchain.cmake") ;;
  arm64-apple-darwin)
    if [ "$(uname -s)" = Darwin ]; then
      export SDKROOT=$(xcrun --show-sdk-path)
      arguments+=("-DCMAKE_C_COMPILER=$(xcrun --find clang)" "-DCMAKE_CXX_COMPILER=$(xcrun --find clang++)" "-DCMAKE_OSX_SYSROOT=$SDKROOT" -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0)
    else
      arguments+=("-DCMAKE_TOOLCHAIN_FILE=$cpkt_root/cmake/toolchains/arm64-apple-darwin.cmake")
      can_run=OFF
    fi ;;
esac
for phase in original relocated-misc relocated-core; do
  selected="$workspace/$phase"
  # A new archive at the same prefix must not reuse cached package discovery.
  rm -f -- "$selected/CMakeCache.txt"
  "$cpkt_cmake" -S "$cpkt_root/tests/sdk-consumers/native" -B "$selected" \
    "${arguments[@]}" "-DCPKT_PREFIX=$prefix" "-DCPKT_CORE_PREFIX=$core" "-DCPKT_CAN_RUN_CONSUMERS=$can_run"
  "$cpkt_cmake" --build "$selected" --parallel "$(cpkt_jobs "$cpkt_binary")"
  if [ "$can_run" = ON ]; then
    "$cpkt_ctest" --test-dir "$selected" --output-on-failure --stop-on-failure --no-tests=error
  fi
  if [ "$phase" = original ]; then
    relocated="$workspace/relocated SDK with spaces"
    cpkt_owned_path "$relocated"
    rm -rf -- "$relocated"
    mkdir -p "$workspace"
    cp -a -- "$prefix" "$relocated"
    prefix=$relocated
  elif [ "$phase" = relocated-misc ]; then
    relocated="$workspace/relocated core SDK with spaces"
    cpkt_owned_path "$relocated"
    rm -rf -- "$relocated"
    cp -a -- "$core" "$relocated"
    core=$relocated
  fi
done
# Consumption and relocation must leave the acquired published bytes unchanged.
"$cpkt_cmake" "-DCPKT_REPO_ROOT=$cpkt_root" "-DCPKT_CORE_TARGET=$target" \
  -DCPKT_CORE_ACTION=validate -P "$cpkt_root/cmake/core-dependency.cmake"
