cmake_minimum_required(VERSION 3.21)
include("${CPKT_ROOT}/tests/test-command.cmake")
set(work "${CPKT_SCRATCH}/logging driver with spaces")
file(MAKE_DIRECTORY "${work}")
file(WRITE "${work}/runner.sh" [=[#!/usr/bin/env bash
set -euo pipefail
[ "$#" = 4 ]
[ "$1" = -L ]
[ "$2" = "${0%/*}/sysroot with spaces" ]
[ "$3" = program ]
[ "$4" = config.json5 ]
case "${DRIVER_RESULT:-pass}" in
  exit) exit 3 ;;
  stdout) printf 'default logger output\n' ;;
  stderr) printf 'default logger error\n' >&2 ;;
esac
printf '[test] OPC UA logging through libpslog passed\n'
]=])
set(command "${CMAKE_COMMAND}" -P "${CPKT_ROOT}/tests/opcua_logging_output_test.cmake"
  -- bash "${work}/runner.sh" -L "${work}/sysroot with spaces" program config.json5)
cpkt_test_command(${command})
foreach(failure exit stdout stderr)
  cpkt_test_failure("Custom OPC UA logger emitted default output or failed"
    "${CMAKE_COMMAND}" -E env "DRIVER_RESULT=${failure}" ${command})
endforeach()
