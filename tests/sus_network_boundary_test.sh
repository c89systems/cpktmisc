#!/usr/bin/env bash
set -euo pipefail
repo=${1:?repository required}
cmake "-DCPKT_ROOT=$repo" -P "$repo/tests/sus_network_boundary_test.cmake"
