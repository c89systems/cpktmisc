cmake_minimum_required(VERSION 3.21)
project(cpktmisc_lifecycle_tests NONE)
enable_testing()
get_filename_component(CPKT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
include("${CPKT_ROOT}/cmake/CpktMutationPaths.cmake")
cpkt_validate_mutation_paths("${CMAKE_BINARY_DIR}/scratch")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/scratch")
foreach(check sdk_native_validation published_core cache_defaults clean_ownership archive_safety)
  add_test(NAME ${check}
    COMMAND "${CMAKE_COMMAND}" "-DCPKT_ROOT=${CPKT_ROOT}" "-DCPKT_SCRATCH=${CMAKE_BINARY_DIR}/scratch"
      -P "${CPKT_ROOT}/tests/${check}_test.cmake")
  set_tests_properties(${check} PROPERTIES TIMEOUT 60 RUN_SERIAL TRUE LABELS lifecycle)
endforeach()
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
  add_test(NAME toolchain_resolver
    COMMAND bash "${CPKT_ROOT}/tests/toolchain_resolver_test.sh")
  set_tests_properties(toolchain_resolver PROPERTIES TIMEOUT 30 RUN_SERIAL TRUE LABELS resolver
    ENVIRONMENT "TMPDIR=${CMAKE_BINARY_DIR}/scratch")
  if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64)$")
    add_test(NAME afl_resolver COMMAND bash "${CPKT_ROOT}/tests/aflpp_resolver_cleanup_test.sh")
    set_tests_properties(afl_resolver PROPERTIES TIMEOUT 30 RUN_SERIAL TRUE LABELS resolver
      ENVIRONMENT "TMPDIR=${CMAKE_BINARY_DIR}/scratch")
  endif()
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
  foreach(check linux_toolchain_sysroot_policy osxcross_linker_cache_refresh)
    add_test(NAME ${check} COMMAND bash "${CPKT_ROOT}/tests/${check}_test.sh" "${CPKT_ROOT}")
    set_tests_properties(${check} PROPERTIES TIMEOUT 30 RUN_SERIAL TRUE LABELS resolver
      ENVIRONMENT "TMPDIR=${CMAKE_BINARY_DIR}/scratch")
  endforeach()
endif()
