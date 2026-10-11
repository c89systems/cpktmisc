# CTest owns native prerequisite fixtures in both standalone and product graphs.
function(cpkt_preflight_wanted name output)
  if(DEFINED CPKT_PREFLIGHT_CASES)
    if(name IN_LIST CPKT_PREFLIGHT_CASES)
      set(${output} ON PARENT_SCOPE)
    else()
      set(${output} OFF PARENT_SCOPE)
    endif()
  elseif(CPKT_BUILD_TESTS AND (CPKT_CAN_RUN_TARGET_EXECUTABLES OR name STREQUAL "sdk_runtime_loader"))
    set(${output} ON PARENT_SCOPE)
  else()
    set(${output} OFF PARENT_SCOPE)
  endif()
endfunction()
function(cpkt_register_preflight_tests repo_root)
  cpkt_preflight_wanted(sdk_runtime_loader wanted)
  if(wanted AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
    cpkt_group_add_test(NAME sdk_runtime_loader COMMAND "${CMAKE_COMMAND}"
      "-DCPKT_REPO=${repo_root}" "-DCPKT_SCRATCH=${CMAKE_BINARY_DIR}" "-DCPKT_TARGET=${CPKT_TARGET_ID}"
      "-DCPKT_CC=${CMAKE_C_COMPILER}" "-DCPKT_READELF=${CMAKE_READELF}" "-DCPKT_SYSROOT=${CMAKE_SYSROOT}"
      "-DCPKT_RUNNER=${CPKT_TEST_EXECUTABLE_PREFIX}" -P "${repo_root}/tests/sdk_runtime_loader_test.cmake")
  endif()
  cpkt_preflight_wanted(patch_series_portability wanted)
  if(wanted)
    cpkt_group_add_test(NAME patch_series_portability COMMAND "${CMAKE_COMMAND}"
      "-DCPKT_SOURCE_DIR=${repo_root}" "-DCPKT_PATCH_TEST_ROOT=${CMAKE_BINARY_DIR}"
      -P "${repo_root}/tests/patch_series_portability_test.cmake")
  endif()
  cpkt_preflight_wanted(source_archive_verify_failure wanted)
  if(wanted AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
    cpkt_group_add_test(NAME source_archive_verify_failure COMMAND "${CMAKE_COMMAND}"
      "-DCPKT_ROOT=${repo_root}" "-DCPKT_SCRATCH=${CMAKE_BINARY_DIR}"
      -P "${repo_root}/tests/source_archive_verify_failure_test.cmake")
  endif()
  foreach(label Ninja Makefiles)
    if(label STREQUAL "Ninja")
      set(generator Ninja)
    else()
      set(generator "Unix Makefiles")
    endif()
    cpkt_preflight_wanted("dependency_install_order_${label}" wanted)
    if(wanted)
      cpkt_group_add_test(NAME dependency_install_order_${label} COMMAND "${CMAKE_COMMAND}"
        "-DCPKT_REPO=${repo_root}" "-DCPKT_SCRATCH=${CMAKE_BINARY_DIR}" "-DCPKT_GENERATOR=${generator}"
        -P "${repo_root}/tests/dependency_install_order_test.cmake")
    endif()
    cpkt_preflight_wanted("open62541_openssl_provenance_${label}" wanted)
    if(wanted AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
      cpkt_group_add_test(NAME open62541_openssl_provenance_${label} COMMAND "${CMAKE_COMMAND}" -P
        "${repo_root}/tests/open62541_openssl_provenance_fixture_test.cmake" "${repo_root}" "${CMAKE_BINARY_DIR}" "${generator}")
    endif()
  endforeach()
endfunction()
