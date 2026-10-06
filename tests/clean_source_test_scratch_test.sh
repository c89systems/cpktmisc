#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <source-dir>\n' "$0" >&2
  exit 2
fi

source_dir=$1
mkdir -p "$source_dir/build"
work_root=$(mktemp -d "$source_dir/build/clean-source-test-scratch.XXXXXXXX")
trap 'cmake -E remove_directory "$work_root"' EXIT

reuse_root="$work_root/reuse"
mkdir -p "$reuse_root/tests"
cp "$source_dir/tests/dependency_reuse_configure_test.sh" "$reuse_root/tests/"
cat > "$work_root/mock-cmake" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -eq 3 && $1 == -E && $2 == remove_directory ]]; then
  exec cmake -E remove_directory "$3"
fi
if [[ $# -eq 12 && $1 == -S && $2 == */source &&
      $3 == -B && $4 == */binary && $5 == -G && $6 == Ninja &&
      $7 == -DCMAKE_MAKE_PROGRAM=* && $8 == -DCMAKE_TOOLCHAIN_FILE=* &&
      $9 == -DCMAKE_BUILD_TYPE=Debug && ${10} == -DCPKT_REPO_ROOT=* &&
      ${11} == -DCPKT_EXTERNAL_ROOT=*/external &&
      ${12} == -DCPKT_DEPENDENCY_BUILD_ROOT=*/dependency-build ]]; then
  [[ ${10#*=} == "${BASH_SOURCE[0]%/mock-cmake}/reuse" ]]
  [[ ${11#*=} == "${2%/source}/external" ]]
  [[ ${12#*=} == "${2%/source}/dependency-build" ]]
  printf 'Generating done\n'
  exit 0
fi
printf 'unexpected CMake invocation: %s\n' "$*" >&2
exit 2
MOCK
chmod +x "$work_root/mock-cmake"
bash "$reuse_root/tests/dependency_reuse_configure_test.sh" \
  "$reuse_root" "$work_root/mock-cmake" Ninja ninja "" Debug
if compgen -G "$reuse_root/build/dependency-reuse.*" > /dev/null; then
  printf 'dependency reuse scratch survived helper cleanup\n' >&2
  exit 1
fi
