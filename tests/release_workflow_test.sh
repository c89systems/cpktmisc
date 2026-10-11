#!/usr/bin/env bash
set -euo pipefail
repo=${1:?repository required}
work=${2:?scratch required}/release-workflow
rm -rf -- "$work"
mkdir -p "$work/scripts"
cp -- "$repo/scripts/release.sh" "$work/scripts/"
cmake "-DCPKT_REPO_ROOT=$repo" -DCPKT_INFO=targets -P "$repo/cmake/lifecycle-info.cmake" > "$work/targets"
cat > "$work/scripts/lifecycle-common.sh" <<'SH'
cpkt_scripts=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cpkt_root=${cpkt_scripts%/scripts}
cpkt_provider=cpktmisc
cpkt_cmake=$cpkt_scripts/cmake-command.sh
cpkt_fail() { printf '%s\n' "$*" >&2; exit 2; }
cpkt_info() { cat "$cpkt_root/targets"; }
cpkt_jobs() { printf '8\n'; }
cpkt_preset() { cpkt_binary=$cpkt_root/build/${1%-release}/misc/Release; }
SH
cat > "$work/scripts/fixture-command.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "${0%/*}/lifecycle-common.sh"
name=${0##*/}
case "$name" in
  lifecycle.sh)
    printf '%s\n' "$1" >> "$cpkt_root/trace"
    [ "${FAIL_AT:-}" != "$1" ] || exit 17
    case "$1" in
      clean) rm -rf -- "$cpkt_root/build" "$cpkt_root/dist" "$cpkt_root/.cache" ;;
      package-source)
        mkdir -p "$cpkt_root/dist"
        printf source > "$cpkt_root/dist/cpktmisc-1.2.3.tar.gz" ;;
      format) printf 'Final release formatted frozen sources\n' >&2; exit 1 ;;
    esac ;;
  release-version.sh) printf '1.2.3\n' ;;
  cpkt-toolchains.sh|core-dependency.sh|cpkt-aflpp.sh)
    printf '%s %s\n' "$name" "$*" >> "$cpkt_root/trace" ;;
  source-archive-verify.sh)
    [ "$#" = 3 ] && [ "$2" = 1.2.3 ] && [ "$3" = --release-build ]
    [ -f "$1" ]
    printf 'source-native-release\n' >> "$cpkt_root/trace"
    [ "${FAIL_AT:-}" != source ] || exit 17
    printf native > "$cpkt_root/dist/cpktmisc-1.2.3-x86_64-linux-gnu.tar.gz" ;;
  package.sh)
    if [ "$1" = package ]; then
      [ "$#" = 7 ] && [ "$3" = misc ] && [ "$7" = selected ]
      target=${5%-release}
      [ "$target" != x86_64-linux-gnu ]
      printf 'package %s\n' "$target" >> "$cpkt_root/trace"
      archive=$cpkt_root/build/package-stage/$target/misc/archives/cpktmisc-1.2.3-$target.tar.gz
      mkdir -p "${archive%/*}"
      printf cross > "$archive"
    else
      [ "$#" = 5 ] && [ "$3" = all ] && [ "$5" = release ]
      while IFS= read -r target; do
        [ -f "$cpkt_root/dist/cpktmisc-1.2.3-$target.tar.gz" ]
      done < "$cpkt_root/targets"
      [ -f "$cpkt_root/dist/cpktmisc-1.2.3-arm64-apple-darwin-smoke-test.zip" ]
      [ -f "$cpkt_root/dist/cpktmisc-1.2.3.tar.gz" ]
      printf '%s\n' "$1" >> "$cpkt_root/trace"
    fi ;;
  cmake-command.sh)
    [ "$#" = 6 ] && [ "$1" = --build ] && [ "$3" = --parallel ] && [ "$4" = 8 ]
    [ "$2" = "$cpkt_root/build/arm64-apple-darwin/misc/Release" ]
    [ "$6" = package-darwin-smoke ]
    printf smoke > "$cpkt_root/dist/cpktmisc-1.2.3-arm64-apple-darwin-smoke-test.zip"
    printf 'darwin-smoke\n' >> "$cpkt_root/trace" ;;
  *) exit 1 ;;
esac
SH
for script in lifecycle release-version cpkt-toolchains core-dependency cpkt-aflpp source-archive-verify package cmake-command; do
  cp "$work/scripts/fixture-command.sh" "$work/scripts/$script.sh"
done
chmod +x "$work/scripts/cmake-command.sh"
unset GROUP PRESET CPKT_RELEASE_PRODUCTION CPKT_RELEASE_VERSION_OVERRIDE
bash "$work/scripts/release.sh" release
{
  printf 'lifecycle-version-contract\nclean\nformat-check\npackage-source\ncpkt-aflpp.sh ensure\n'
  while IFS= read -r target; do
    printf 'cpkt-toolchains.sh ensure %s\ncore-dependency.sh --target %s\n' "$target" "$target"
  done < "$work/targets"
  printf 'source-native-release\ndebug\nclangd-surface\nvalgrind\nfuzz-smoke\n'
  while IFS= read -r target; do
    [ "$target" = x86_64-linux-gnu ] || printf 'package %s\n' "$target"
  done < "$work/targets"
  printf 'darwin-smoke\npackage-checksums\npackage-verify\n'
} > "$work/expected"
cmp "$work/expected" "$work/trace"
rm -- "$work/trace"
mkdir -p "$work/build"
printf keep > "$work/build/keep"
if FAIL_AT=lifecycle-version-contract bash "$work/scripts/release.sh" release; then exit 1; fi
[ "$(cat "$work/trace")" = lifecycle-version-contract ]
[ "$(cat "$work/build/keep")" = keep ]
rm -- "$work/trace"
if FAIL_AT=source bash "$work/scripts/release.sh" release; then exit 1; fi
[ "$(tail -n 1 "$work/trace")" = source-native-release ]
