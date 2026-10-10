#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=${1:-$(CDPATH= cd -- "$script_dir/.." && pwd)}

# Check each owned recipe separately: another dependency's PIC flags cannot
# hide a missing flag in the static archive used by a shared consumer.
require_pic() {
  local recipe=$1 needle=$2 expected=$3
  local deps_file="$repo_root/cmake/dependencies/${recipe#cpkt_add_}.cmake"
  if ! awk -v recipe="$recipe" -v needle="$needle" -v expected="$expected" '
    $0 == "function(" recipe ")" { inside = 1; next }
    inside && /^endfunction/ { inside = 0 }
    inside && index($0, needle) { count++ }
    END { exit count == expected ? 0 : 1 }
  ' "$deps_file"; then
    printf '%s must retain %s PIC setting(s): %s\n' "$recipe" "$expected" "$needle" >&2
    exit 1
  fi
}

require_pic cpkt_add_libpng '-DCMAKE_POSITION_INDEPENDENT_CODE=ON' 1
require_pic cpkt_add_libharu '-DCMAKE_POSITION_INDEPENDENT_CODE=ON' 2
require_pic cpkt_add_miniaudio '-fPIC' 1
require_pic cpkt_add_whisper '-DCMAKE_POSITION_INDEPENDENT_CODE=ON' 1
require_pic cpkt_add_open62541 '-DCMAKE_POSITION_INDEPENDENT_CODE=ON' 1

printf '[test] owned static dependency PIC policy passed\n'
