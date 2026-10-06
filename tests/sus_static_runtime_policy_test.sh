#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  printf 'usage: sus_static_runtime_policy_test.sh <source-dir>\n' >&2
  exit 2
fi

source_dir=$1
top_cmake=$source_dir/CMakeLists.txt

require_file_contains() {
  file=$1
  needle=$2
  description=$3

  if ! grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    printf 'missing sus static-runtime policy: %s\n' "$description" >&2
    printf 'expected to find: %s\n' "$needle" >&2
    printf 'in: %s\n' "$file" >&2
    exit 1
  fi
}

require_file_contains "$top_cmake" \
  'COMMAND "${CMAKE_CXX_COMPILER}" -print-file-name=libstdc++.a' \
  'top-level configure must discover static libstdc++.a from the selected C++ compiler'
require_file_contains "$top_cmake" \
  'COMMAND "${CMAKE_CXX_COMPILER}" -print-libgcc-file-name' \
  'top-level configure must discover static libgcc.a from the selected C++ compiler'

python3 "$source_dir/tests/sus_split_runtime_policy_test.py" "$source_dir"

# Runtime separation, shipment and ordered static closure are asserted against
# this provider's inventory and metadata by the fixture above. Skill prose is
# owned and tested by core.
