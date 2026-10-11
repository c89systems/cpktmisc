#!/usr/bin/env bash
set -euo pipefail
repo=${1:?source required}
scratch=${2:?scratch required}
mkdir -p "$scratch"
work=$(mktemp -d "$scratch/sus-vox-dump.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/project/scripts" "$work/project/build" "$work/bin" "$work/cache"
cp "$repo/scripts/run-sus-vox-intro.sh" "$work/project/scripts/"
printf 'fixture\n' > "$work/cache/intro.mp3"
printf 'fixture\n' > "$work/project/build/CMakeCache.txt"
cat > "$work/project/scripts/build.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "${CPKT_FAKE_BUILD:?}"
EOF
cat > "$work/bin/example" <<'EOF'
#!/bin/sh
test -f "${CPKT_KEEP_FILE:?}"
EOF
chmod +x "$work/bin/example"
for dump in "$work/existing directory" "$work/project"; do
  mkdir -p "$dump"
  printf 'caller data\n' > "$dump/keep.txt"
  CPKT_FAKE_BUILD="$work/project/build" CPKT_KEEP_FILE="$dump/keep.txt" \
  CPKT_SUS_VOX_INTRO_CACHE="$work/cache" CPKT_SUS_VOX_INTRO_DUMP_DIR="$dump" \
    bash "$work/project/scripts/run-sus-vox-intro.sh" "$work/bin/example" "$work/project/build"
  test "$(cat "$dump/keep.txt")" = 'caller data'
  test -f "$work/project/scripts/run-sus-vox-intro.sh"
done
