#!/usr/bin/env bash
set -euo pipefail
repo=${1:?repository required}
cmake "-DCPKT_ROOT=$repo" -P "$repo/tests/sus_static_runtime_policy_test.cmake"
