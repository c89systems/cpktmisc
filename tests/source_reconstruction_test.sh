#!/usr/bin/env bash
set -euo pipefail
repo=${1:?repository required}
work=${2:?scratch required}/source-reconstruction
rm -rf -- "$work"
mkdir -p "$work/scripts"
cp -- "$repo/scripts/source-reconstruct.sh" "$work/scripts/"
cat > "$work/scripts/lifecycle-common.sh" <<'SH'
cpkt_scripts=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cpkt_root=${cpkt_scripts%/scripts}
cpkt_provider=cpktmisc
cpkt_fail() { printf '%s\n' "$*" >&2; exit 2; }
SH
cat > "$work/scripts/core-dependency.sh" <<'SH'
set -euo pipefail
root=${BASH_SOURCE[0]%/scripts/*}
printf 'core\n' >> "$root/trace"
mkdir -p "$root/.cache"
SH
cat > "$work/scripts/build.sh" <<'SH'
set -euo pipefail
root=${BASH_SOURCE[0]%/scripts/*}
[ -d "$root/.cache" ]
printf 'build\n' >> "$root/trace"
SH
cat > "$work/scripts/package.sh" <<'SH'
set -euo pipefail
root=${BASH_SOURCE[0]%/scripts/*}
printf '%s\n' "$1" >> "$root/trace"
SH
bash "$work/scripts/source-reconstruct.sh"
printf 'core\nbuild\npackage-stage\npackage-checksums\npackage-verify\n' > "$work/expected"
cmp "$work/expected" "$work/trace"
rm -- "$work/trace"
if bash "$work/scripts/source-reconstruct.sh" release; then
  printf 'Dirty compiled state accepted\n' >&2; exit 1
fi
[ ! -e "$work/trace" ]
rm -rf -- "$work/.cache"
bash "$work/scripts/source-reconstruct.sh" release
cmp "$work/expected" "$work/trace"
