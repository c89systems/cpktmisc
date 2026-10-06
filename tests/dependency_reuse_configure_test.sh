#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  printf 'usage: %s <source-dir> <cmake> <generator> <make-program> <toolchain-file> <build-type>\n' "$0" >&2
  exit 2
fi

source_dir=$1
cmake_command=$2
generator=$3
make_program=$4
toolchain_file=$5
build_type=$6
mkdir -p "$source_dir/build"
work_dir=$(mktemp -d "$source_dir/build/dependency-reuse.XXXXXXXX")
trap '"$cmake_command" -E remove_directory "$work_dir"' EXIT HUP INT TERM

# Configure a real owned recipe against tiny caller-owned artifacts. A helper
# must never configure the optional SDK or demand a published core installation.
mkdir -p "$work_dir/external/miniaudio/install/include/miniaudio"
mkdir -p "$work_dir/source" "$work_dir/external/miniaudio/install/include" "$work_dir/external/miniaudio/install/lib"
printf '/* fixture header */\n' > "$work_dir/external/miniaudio/install/include/miniaudio/miniaudio.h"
printf 'static fixture\n' > "$work_dir/external/miniaudio/install/lib/libminiaudio.a"
printf 'shared fixture\n' > "$work_dir/external/miniaudio/install/lib/libminiaudio.so"
cat > "$work_dir/source/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.21)
project(owned_dependency_reuse C)
find_package(Threads REQUIRED)
set(CPKT_BUILD_DEPENDENCIES OFF)
set(CPKT_TARGET_ARCH x86_64)
set(CPKT_TARGET_OS linux)
set(CPKT_TARGET_LIBC gnu)
set(CPKT_DEPENDENCY_BUILD_TYPE Release)
include("${CPKT_REPO_ROOT}/cmake/CpktDependencies.cmake")
cpkt_add_miniaudio()
get_property(producers GLOBAL PROPERTY CPKT_DEPENDENCY_TARGETS)
if(producers)
  message(FATAL_ERROR "Disabled owned recipe created producers: ${producers}")
endif()
foreach(linkage static shared)
  add_executable(consumer_${linkage} probe.c)
  target_link_libraries(consumer_${linkage} PRIVATE cpkt::miniaudio_${linkage})
endforeach()
CMAKE
printf 'int main(void) { return 0; }\n' > "$work_dir/source/probe.c"
artifacts_before=$(find "$work_dir/external" -type f -exec sha256sum {} +)
for iteration in 1 2; do
  "$cmake_command" -S "$work_dir/source" -B "$work_dir/binary" -G "$generator" \
    -DCMAKE_MAKE_PROGRAM="$make_program" \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
    -DCMAKE_BUILD_TYPE="$build_type" \
    -DCPKT_REPO_ROOT="$source_dir" \
    -DCPKT_EXTERNAL_ROOT="$work_dir/external" \
    -DCPKT_DEPENDENCY_BUILD_ROOT="$work_dir/dependency-build" > "$work_dir/configure.log" 2>&1 || {
      cat "$work_dir/configure.log" >&2
      exit 1
    }
  if ! grep -Fq 'Generating done' "$work_dir/configure.log"; then
    cat "$work_dir/configure.log" >&2
    printf 'dependency-reuse configure did not generate a build graph\n' >&2
    exit 1
  fi
done
[[ "$artifacts_before" == "$(find "$work_dir/external" -type f -exec sha256sum {} +)" ]] || {
  printf 'disabled recipe modified caller-owned dependency artifacts\n' >&2
  exit 1
}
[[ ! -e "$work_dir/dependency-build" ]] || {
  printf 'disabled recipe created a dependency build root\n' >&2
  exit 1
}
printf '[test] owned static/shared dependency reuse configured twice without producers\n'
