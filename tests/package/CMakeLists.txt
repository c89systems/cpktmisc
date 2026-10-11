cmake_minimum_required(VERSION 3.21)
project(cpkt_package_checks NONE)
enable_testing()
include("${CPKT_SOURCE}/cmake/CpktMutationPaths.cmake")
cpkt_validate_mutation_paths("${CMAKE_BINARY_DIR}/sdk" "${CMAKE_BINARY_DIR}/archive.passed")
file(CONFIGURE OUTPUT "${CMAKE_BINARY_DIR}/package.inputs"
  CONTENT "${CPKT_ARCHIVE}\n${CPKT_TARGET}\n${CPKT_VERSION}\n${CPKT_TOOL}\n${CPKT_NM}\n${CPKT_AR}\n" @ONLY)
add_test(NAME package_archive
  COMMAND "${CMAKE_COMMAND}" "-DCPKT_SOURCE=${CPKT_SOURCE}" "-DCPKT_ARCHIVE=${CPKT_ARCHIVE}"
    "-DCPKT_PREFIX=${CMAKE_BINARY_DIR}/sdk" "-DCPKT_TARGET=${CPKT_TARGET}"
    "-DCPKT_VERSION=${CPKT_VERSION}" "-DCPKT_TOOL=${CPKT_TOOL}" "-DCPKT_NM=${CPKT_NM}" "-DCPKT_AR=${CPKT_AR}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/archive_test.cmake")
set_tests_properties(package_archive PROPERTIES TIMEOUT 120 RUN_SERIAL TRUE)
add_test(NAME package_core_import COMMAND "${CMAKE_COMMAND}"
  "-DCPKT_SOURCE=${CPKT_SOURCE}" "-DCPKT_PREFIX=${CMAKE_BINARY_DIR}/sdk"
  "-DCPKT_CORE_PREFIX=${CPKT_SOURCE}/.cache/cpkt/${CPKT_TARGET}/install"
  "-DCPKT_TARGET=${CPKT_TARGET}" "-DCPKT_WORK=${CMAKE_BINARY_DIR}"
  -P "${CMAKE_CURRENT_SOURCE_DIR}/core_import_test.cmake")
set_tests_properties(package_core_import PROPERTIES TIMEOUT 120 RUN_SERIAL TRUE)
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/archive.passed"
  COMMAND "${CMAKE_COMMAND}" -E rm -f "${CMAKE_BINARY_DIR}/archive.passed"
  COMMAND "${CMAKE_CTEST_COMMAND}" --test-dir "${CMAKE_BINARY_DIR}"
    -R "^package_archive$" --output-on-failure --no-tests=error
  COMMAND "${CMAKE_COMMAND}" -E touch "${CMAKE_BINARY_DIR}/archive.passed"
  DEPENDS "${CPKT_ARCHIVE}" "${CMAKE_BINARY_DIR}/package.inputs" "${CMAKE_CURRENT_SOURCE_DIR}/archive_test.cmake"
    "${CPKT_SOURCE}/cmake/extract-release-archive.cmake" "${CPKT_SOURCE}/cmake/gnu_tar.cmake"
    "${CPKT_SOURCE}/cmake/CpktMiscValidate.cmake" "${CPKT_SOURCE}/cmake/package_inspection.cmake"
    "${CPKT_SOURCE}/cmake/CpktPublishedCore.cmake"
    "${CPKT_SOURCE}/dependencies/cpkt.json" "${CPKT_SOURCE}/cmake/components.json"
    "${CPKT_SOURCE}/tests/privacy_scan.cmake" VERBATIM)
add_custom_target(verify_archive DEPENDS "${CMAKE_BINARY_DIR}/archive.passed")
file(GLOB_RECURSE consumer_inputs CONFIGURE_DEPENDS LIST_DIRECTORIES FALSE
  "${CPKT_SOURCE}/tests/sdk-consumers/*" "${CPKT_SOURCE}/examples/*")
file(GLOB codec_consumer_inputs CONFIGURE_DEPENDS "${CPKT_SOURCE}/tests/*_facade_test.c")
list(APPEND consumer_inputs ${codec_consumer_inputs} "${CPKT_SOURCE}/tests/native_codecs_test.c")
add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/consumers.passed"
  COMMAND "${CMAKE_COMMAND}" -E rm -f "${CMAKE_BINARY_DIR}/consumers.passed"
  COMMAND "${CMAKE_CTEST_COMMAND}" --test-dir "${CMAKE_BINARY_DIR}"
    -R "^package_core_import$" --output-on-failure --no-tests=error
  COMMAND bash "${CPKT_SOURCE}/scripts/package-consumers.sh" "${CMAKE_BINARY_DIR}/sdk"
    "${CPKT_TARGET}" "${CMAKE_BINARY_DIR}/consumers"
  COMMAND "${CMAKE_COMMAND}" -E touch "${CMAKE_BINARY_DIR}/consumers.passed"
  DEPENDS "${CMAKE_BINARY_DIR}/archive.passed" ${consumer_inputs}
    "${CMAKE_CURRENT_SOURCE_DIR}/core_import_test.cmake" "${CPKT_SOURCE}/tests/test-command.cmake"
    "${CPKT_SOURCE}/scripts/package-consumers.sh" "${CPKT_SOURCE}/cmake/components.json"
    "${CPKT_SOURCE}/cmake/CpktLocalRuntime.cmake"
    "${CPKT_SOURCE}/cmake/CpktReadOnlyToolchain.cmake" "${CPKT_SOURCE}/cmake/CpktToolchainDiscovery.cmake"
    "${CPKT_SOURCE}/cmake/toolchains/arm64-apple-darwin.cmake" VERBATIM)
add_custom_target(verify_package DEPENDS "${CMAKE_BINARY_DIR}/consumers.passed")
if(CPKT_SMOKE_ARCHIVE)
  file(CONFIGURE OUTPUT "${CMAKE_BINARY_DIR}/smoke.inputs" CONTENT "${CPKT_SMOKE_ARCHIVE}\n" @ONLY)
  if(NOT CPKT_TARGET STREQUAL "arm64-apple-darwin")
    message(FATAL_ERROR "Smoke ZIP verification requires the Darwin SDK")
  endif()
  add_test(NAME darwin_smoke_zip COMMAND "${CMAKE_COMMAND}"
    "-DCPKT_SOURCE=${CPKT_SOURCE}" "-DCPKT_SMOKE_ARCHIVE=${CPKT_SMOKE_ARCHIVE}"
    "-DCPKT_PREFIX=${CMAKE_BINARY_DIR}/sdk" "-DCPKT_CORE_PREFIX=${CPKT_SOURCE}/.cache/cpkt/${CPKT_TARGET}/install" "-DCPKT_WORK=${CMAKE_BINARY_DIR}"
    "-DCPKT_TOOL=${CPKT_TOOL}" -P "${CMAKE_CURRENT_SOURCE_DIR}/smoke_test.cmake")
  set_tests_properties(darwin_smoke_zip PROPERTIES TIMEOUT 120 RUN_SERIAL TRUE)
  add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/smoke.passed"
    COMMAND "${CMAKE_COMMAND}" -E rm -f "${CMAKE_BINARY_DIR}/smoke.passed"
    COMMAND "${CMAKE_CTEST_COMMAND}" --test-dir "${CMAKE_BINARY_DIR}"
      -R "^darwin_smoke_zip$" --output-on-failure --no-tests=error
    COMMAND "${CMAKE_COMMAND}" -E touch "${CMAKE_BINARY_DIR}/smoke.passed"
    DEPENDS "${CPKT_SMOKE_ARCHIVE}" "${CMAKE_BINARY_DIR}/smoke.inputs" "${CMAKE_BINARY_DIR}/archive.passed"
      "${CMAKE_CURRENT_SOURCE_DIR}/smoke_test.cmake" "${CPKT_SOURCE}/tests/test-command.cmake"
      "${CPKT_SOURCE}/cmake/package_inspection.cmake" "${CPKT_SOURCE}/tests/privacy_scan.cmake"
    VERBATIM)
  add_custom_target(verify_smoke DEPENDS "${CMAKE_BINARY_DIR}/smoke.passed")
  add_dependencies(verify_package verify_smoke)
endif()
