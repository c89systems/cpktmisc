#!/usr/bin/env sh
set -eu

if [ "${CPKT_SDK_PREFIX:-}" = "" ]; then
  printf 'CPKT_SDK_PREFIX is required and must point at an extracted cpkt SDK\n' >&2
  exit 2
fi

CPKT_SDK_PREFIX=$(CDPATH= cd -- "$CPKT_SDK_PREFIX" && pwd -P)

cc=${CC:-cc}
pkg_config=${PKG_CONFIG:-pkg-config}
output=${1:-./cpkt_audio_sus_c89_example}
# Remaining arguments are individual link flags, including paths with spaces.
if [ "$#" -gt 0 ]; then shift; fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
output_dir=$(dirname -- "$output")

mkdir -p "$output_dir"

PKG_CONFIG_PATH="$CPKT_SDK_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PKG_CONFIG_PATH
validation=$(mktemp -d "$output_dir/.cpkt-sdk-validation.XXXXXX")
trap 'rm -rf -- "$validation"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
cmake -S "$CPKT_SDK_PREFIX/lib/cmake/CpktMisc/pkg-config" \
  -B "$validation" \
  "-DCPKT_SDK_PREFIX=$CPKT_SDK_PREFIX" "-DPKG_CONFIG_EXECUTABLE=$pkg_config"

pkg_config_cflags=$(
    "$pkg_config" --cflags cpkt-audio cpkt-sus
)
pkg_config_libs=$(
    "$pkg_config" --static --libs cpkt-audio cpkt-sus
)

"$cc" ${CPKT_EXAMPLE_CFLAGS:-} -std=c89 -Wall -Wextra -Wpedantic \
  "$script_dir/main.c" -o "$output" \
  $pkg_config_cflags \
  $pkg_config_libs \
  "$@"
