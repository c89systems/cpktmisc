#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: fuzz_toolchain_policy_test.sh <source-dir>\n' >&2
  exit 2
fi

source_dir=$1
if [[ -z ${CPKT_OPERATION_FD:-} ]]; then
  exec bash "$source_dir/scripts/operation.sh" --group all -- bash "$0" "$source_dir"
fi
mkdir -p "$source_dir/build/fixtures"
work_dir=$(mktemp -d "$source_dir/build/fixtures/fuzz-policy.XXXXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

# Evaluate the actual top-level AFL policy in a standalone native configure.
# The optional SDK prerequisite check must not mask these diagnostics.
mkdir -p "$work_dir/source"
cat > "$work_dir/source/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.21)
project(fuzz_policy C CXX)
file(READ "${CPKT_REPO_ROOT}/CMakeLists.txt" top)
string(FIND "${top}" "if(CPKT_ENABLE_FUZZING)\n" start)
if(start LESS 0)
  message(FATAL_ERROR "Top-level AFL policy is missing")
endif()
string(SUBSTRING "${top}" ${start} -1 tail)
string(FIND "${tail}" "include(cmake/CpktDependencies.cmake)" end)
if(end LESS 0)
  message(FATAL_ERROR "Top-level AFL policy boundary is missing")
endif()
string(SUBSTRING "${tail}" 0 ${end} policy)
cmake_language(EVAL CODE "${policy}")
CMAKE

check_refusal() {
  local name=$1 diagnostic=$2
  shift 2
  local output
  if output=$(cmake -S "$work_dir/source" -B "$work_dir/$name" -G Ninja \
    -DCPKT_REPO_ROOT="$source_dir" -DCPKT_ENABLE_FUZZING=ON "$@" 2>&1); then
    printf 'CPKT_ENABLE_FUZZING accepted %s\n' "$name" >&2
    exit 1
  fi
  if [[ "$output" != *"$diagnostic"* ]]; then
    printf 'missing actionable AFL++ diagnostic\n%s\n' "$output" >&2
    exit 1
  fi
}
check_refusal no-afl-toolchain 'CPKT_ENABLE_FUZZING requires the pinned AFL++ toolchain'
check_refusal no-afl-wrappers 'CPKT_ENABLE_FUZZING requires the pinned AFL++ compiler wrappers' \
  -DCPKT_AFLPP_ROOT="$work_dir/fake-afl"
# Native symlinks provide compiler identity for configure only; no fuzz target
# or toolchain provisioning is invoked.
mkdir -p "$work_dir/wrappers"
ln -s "$(command -v cc)" "$work_dir/wrappers/cpkt-afl-gcc"
ln -s "$(command -v c++)" "$work_dir/wrappers/cpkt-afl-g++"
cmake -S "$work_dir/source" -B "$work_dir/valid-wrappers" -G Ninja \
  -DCPKT_REPO_ROOT="$source_dir" -DCPKT_ENABLE_FUZZING=ON \
  -DCPKT_AFLPP_ROOT="$work_dir/fake-afl" \
  -DCMAKE_C_COMPILER="$work_dir/wrappers/cpkt-afl-gcc" \
  -DCMAKE_CXX_COMPILER="$work_dir/wrappers/cpkt-afl-g++" > "$work_dir/valid.log" 2>&1 || {
    cat "$work_dir/valid.log" >&2
    exit 1
  }
printf '[test] native AFL policy refusals and wrapper acceptance passed without an SDK configure\n'
