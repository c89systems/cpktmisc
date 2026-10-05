cmake_minimum_required(VERSION 3.21)
include(cmake/CpktGroups.cmake)
include(cmake/CpktOperation.cmake)
execute_process(
  COMMAND "${CMAKE_SOURCE_DIR}/scripts/release-version.sh" "${CMAKE_SOURCE_DIR}"
  OUTPUT_VARIABLE CPKT_PROJECT_VERSION
  RESULT_VARIABLE CPKT_PROJECT_VERSION_RESULT
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT CPKT_PROJECT_VERSION_RESULT EQUAL 0)
  message(FATAL_ERROR "failed to resolve cpkt release version")
endif()
project(cpktmisc VERSION "${CPKT_PROJECT_VERSION}" LANGUAGES C CXX)
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin" AND CPKT_OSXCROSS_ROOT)
  set(_cpkt_osxcross_link_launcher "${_cpkt_build_launcher}")
  foreach(_cpkt_argument IN ITEMS "${CMAKE_COMMAND}" "-E" "env"
        "LD_LIBRARY_PATH=${CPKT_OSXCROSS_ROOT}/lib:$ENV{LD_LIBRARY_PATH}")
    string(REPLACE "'" "'\"'\"'" _cpkt_quoted_argument "${_cpkt_argument}")
    string(APPEND _cpkt_osxcross_link_launcher " '${_cpkt_quoted_argument}'")
  endforeach()
  set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK
      "${_cpkt_osxcross_link_launcher}")
endif()
if(CPKT_DEPENDENCY_PRODUCER AND CMAKE_EXPORT_COMPILE_COMMANDS)
  # Dependency-only graphs contain no project-owned compile commands.
  set(CMAKE_EXPORT_COMPILE_COMMANDS OFF)
endif()
include(CTest)
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
option(CPKT_BUILD_DEPENDENCIES "Download and build pinned third-party dependencies." ON)
option(CPKT_BUILD_TESTS "Build ABI/link smoke tests for published dependency artifacts." ON)
option(CPKT_ALLOW_DEPENDENCY_ROOT_OVERRIDE "Honor explicitly provided dependency roots even when they differ from this compiler's default cache key." OFF)
option(CPKT_CALLER_OWNED_DEPENDENCY_ROOTS "Treat explicitly overridden dependency roots as caller-owned and skip repo-local lifecycle invalidation for them." OFF)
option(CPKT_ENABLE_FUZZING "Build AFL++ GCC-plugin facade fuzz targets." OFF)
option(CPKT_FACADE_ONLY "Build only repo-owned facade hardening targets." OFF)
if(CPKT_BUILD_DEPENDENCIES AND NOT CPKT_DEPENDENCY_PRODUCER)
  message(FATAL_ERROR "Use scripts/group-build.py configure/build to prepare the single owning producer; repository consumer graphs import successful output only")
endif()
option(CPKT_SUS_CPU_ONLY "Build the cpkt_sus whisper.cpp dependency set with CPU backends only." ON)
function(cpkt_normalize_arch arch out_var)
  string(TOLOWER "${arch}" _cpkt_arch)
  if(_cpkt_arch STREQUAL "amd64")
    set(_cpkt_arch "x86_64")
  elseif(_cpkt_arch STREQUAL "arm64")
    set(_cpkt_arch "aarch64")
  elseif(_cpkt_arch STREQUAL "arm")
    set(_cpkt_arch "armhf")
  endif()
  set(${out_var} "${_cpkt_arch}" PARENT_SCOPE)
endfunction()
include(cmake/CpktDependencyContract.cmake)
function(cpkt_target_executables_runnable out_var)
  string(TOLOWER "${CMAKE_SYSTEM_NAME}" _cpkt_target_os)
  string(TOLOWER "${CMAKE_HOST_SYSTEM_NAME}" _cpkt_host_os)
  cpkt_normalize_arch("${CMAKE_SYSTEM_PROCESSOR}" _cpkt_target_arch)
  cpkt_normalize_arch("${CMAKE_HOST_SYSTEM_PROCESSOR}" _cpkt_host_arch)
  if(CMAKE_CROSSCOMPILING_EMULATOR)
    set(${out_var} ON PARENT_SCOPE)
  elseif(_cpkt_target_os STREQUAL _cpkt_host_os AND _cpkt_target_arch STREQUAL _cpkt_host_arch)
    set(${out_var} ON PARENT_SCOPE)
  else()
    set(${out_var} OFF PARENT_SCOPE)
  endif()
endfunction()
cpkt_target_executables_runnable(CPKT_CAN_RUN_TARGET_EXECUTABLES)
include(cmake/CpktLocalRuntime.cmake)
set(CPKT_TEST_EXECUTABLE_PREFIX)
if(CMAKE_CROSSCOMPILING AND CMAKE_CROSSCOMPILING_EMULATOR)
  set(CPKT_TEST_EXECUTABLE_PREFIX ${CMAKE_CROSSCOMPILING_EMULATOR})
endif()
function(cpkt_add_repo_warning_errors target_name)
  if(NOT TARGET "${target_name}")
    return()
  endif()
  get_target_property(_cpkt_target_type ${target_name} TYPE)
  if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(${target_name} PRIVATE
          -Wall
          -Wextra
          -Wpedantic
          -Werror
          "-ffile-prefix-map=${CMAKE_SOURCE_DIR}=src"
          "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build"
          "-fdebug-prefix-map=${CMAKE_SOURCE_DIR}=src"
          "-fdebug-prefix-map=${CMAKE_BINARY_DIR}=build")
    if(NOT _cpkt_target_type STREQUAL "STATIC_LIBRARY")
      if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        target_link_options(${target_name} PRIVATE LINKER:-fatal_warnings)
      else()
        target_link_options(${target_name} PRIVATE LINKER:--fatal-warnings)
      endif()
    endif()
  elseif(MSVC)
    target_compile_options(${target_name} PRIVATE /W4 /WX)
    if(NOT _cpkt_target_type STREQUAL "STATIC_LIBRARY")
      target_link_options(${target_name} PRIVATE LINKER:/WX)
    endif()
  endif()
endfunction()
function(cpkt_configure_c89_target target_name)
  if(NOT TARGET "${target_name}")
    return()
  endif()
  if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(${target_name} PRIVATE
          -std=c89
          -Wall
          -Wextra
          -Wpedantic
          -pedantic-errors)
  endif()
endfunction()
function(cpkt_apply_auth_export_catalog target_name catalog_name)
  if(NOT TARGET "${target_name}")
    return()
  endif()
  set(_catalog "${CMAKE_SOURCE_DIR}/cmake/exports/${catalog_name}.txt")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_catalog}")
  file(STRINGS "${_catalog}" _symbols REGEX "^cpkt_")
  if(NOT _symbols)
    message(FATAL_ERROR "empty authentication export catalog: ${_catalog}")
  endif()
  if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(_linker_file "${CMAKE_BINARY_DIR}/${catalog_name}.exports")
    set(_linker_contents "")
    foreach(_symbol IN LISTS _symbols)
      string(APPEND _linker_contents "_${_symbol}\n")
    endforeach()
    target_link_options(${target_name} PRIVATE
          "-Wl,-exported_symbols_list,${_linker_file}")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(_linker_file "${CMAKE_BINARY_DIR}/${catalog_name}.map")
    set(_linker_contents "{\n  global:\n")
    foreach(_symbol IN LISTS _symbols)
      string(APPEND _linker_contents "    ${_symbol};\n")
    endforeach()
    string(APPEND _linker_contents "  local: *;\n};\n")
    target_link_options(${target_name} PRIVATE
          "-Wl,--version-script,${_linker_file}" "-Wl,--exclude-libs,ALL")
  endif()
  if(DEFINED _linker_file)
    if(EXISTS "${_linker_file}")
      file(READ "${_linker_file}" _previous_linker_contents)
    endif()
    if(NOT "${_previous_linker_contents}" STREQUAL "${_linker_contents}")
      file(WRITE "${_linker_file}" "${_linker_contents}")
    endif()
    set_property(TARGET ${target_name} APPEND PROPERTY LINK_DEPENDS
          "${_linker_file}")
  endif()
endfunction()
function(cpkt_configure_c89_lua_native_header_target target_name)
  if(NOT TARGET "${target_name}")
    return()
  endif()
  cpkt_configure_c89_target(${target_name})
  if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(${target_name} PRIVATE
          -Wno-long-long
          -DLLONG_MAX=9223372036854775807LL
          -DLLONG_MIN=-9223372036854775807LL-1LL
          -DULLONG_MAX=18446744073709551615ULL)
  endif()
endfunction()
function(cpkt_add_lua_runtime_mock_test target_name source_name)
  cpkt_inventory_selected(targets "${target_name}" _selected)
  if(NOT _selected)
    return()
  endif()
  cpkt_group_add_executable(${target_name}
      src/lua_runtime.c
      tests/lua_mock/lua_mock.c
      ${source_name})
  cpkt_group_use_local_runtime(${target_name})
  target_compile_options(${target_name} PRIVATE -std=c99)
  cpkt_add_repo_warning_errors(${target_name})
  target_include_directories(${target_name} PRIVATE
      "${CMAKE_SOURCE_DIR}/tests/lua_mock/include"
      "${CMAKE_SOURCE_DIR}/include")
endfunction()
function(cpkt_configure_afl_target target_name)
  if(NOT TARGET "${target_name}")
    return()
  endif()
  if(NOT DEFINED CPKT_AFLPP_ROOT OR "${CPKT_AFLPP_ROOT}" STREQUAL "")
    message(FATAL_ERROR
          "CPKT_ENABLE_FUZZING requires the pinned AFL++ toolchain; "
          "configure with the fuzz or opcua-fuzz preset.")
  endif()
  if(NOT EXISTS "${CPKT_AFLPP_ROOT}/bin/afl-fuzz" OR
        NOT EXISTS "${CPKT_AFLPP_ROOT}/lib/afl/afl-gcc-pass.so")
    message(FATAL_ERROR
          "CPKT_ENABLE_FUZZING requires a complete pinned AFL++ toolchain at "
          "CPKT_AFLPP_ROOT=${CPKT_AFLPP_ROOT}.")
  endif()
  if(NOT CMAKE_C_COMPILER MATCHES "/cpkt-afl-gcc$" OR
        NOT CMAKE_CXX_COMPILER MATCHES "/cpkt-afl-g\\+\\+$")
    message(FATAL_ERROR
          "CPKT_ENABLE_FUZZING requires the pinned AFL++ compiler wrappers; "
          "configure with the fuzz or opcua-fuzz preset.")
  endif()
  target_sources(${target_name} PRIVATE "${CMAKE_SOURCE_DIR}/fuzz/afl_input_driver.c")
  target_compile_options(${target_name} PRIVATE -std=c99)
  cpkt_add_repo_warning_errors(${target_name})
endfunction()
function(cpkt_register_local_runtime_checks)
  get_property(_cpkt_local_tests DIRECTORY PROPERTY TESTS)
  foreach(_cpkt_test IN LISTS _cpkt_local_tests)
    get_test_property(${_cpkt_test} ENVIRONMENT _cpkt_test_environment)
    if(_cpkt_test_environment MATCHES "(^|;)LD_LIBRARY_PATH=")
      message(FATAL_ERROR "Native test ${_cpkt_test} exports LD_LIBRARY_PATH; use private executable runtime paths")
    endif()
  endforeach()
  if(TARGET cpkt_audio_shared)
    cpkt_group_add_test(NAME local_runtime_rejects_shared_library
          COMMAND bash "${CMAKE_SOURCE_DIR}/tests/local_executable_runtime_policy_test.sh"
            "${CPKT_RUNTIME_LOADER}" "$<TARGET_FILE:cpkt_audio_shared>")
    cpkt_group_set_tests_properties(local_runtime_rejects_shared_library PROPERTIES WILL_FAIL TRUE)
  endif()
  get_property(_cpkt_local_targets DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
  set(_cpkt_local_executables)
  foreach(_cpkt_target IN LISTS _cpkt_local_targets)
    get_target_property(_cpkt_type ${_cpkt_target} TYPE)
    if(_cpkt_type STREQUAL "EXECUTABLE")
      list(APPEND _cpkt_local_executables "$<TARGET_FILE:${_cpkt_target}>")
    endif()
  endforeach()
  if(CPKT_COMPOSITION_ONLY)
    foreach(_group core db misc)
      file(GLOB _cpkt_owner_files "${CMAKE_SOURCE_DIR}/build/${CPKT_TARGET_ID}/${_group}/${CMAKE_BUILD_TYPE}/*")
      foreach(_file IN LISTS _cpkt_owner_files)
        if(NOT IS_DIRECTORY "${_file}")
          file(READ "${_file}" _magic LIMIT 4 HEX)
          if(_magic STREQUAL "7f454c46" AND NOT _file MATCHES "[.](so([.][0-9]+)*|o)$")
            list(APPEND _cpkt_local_executables "${_file}")
          endif()
        endif()
      endforeach()
    endforeach()
  endif()
  set(_cpkt_runtime_policy_name local_executable_runtime_policy)
  if(NOT CPKT_GROUP STREQUAL "core")
    string(APPEND _cpkt_runtime_policy_name "_${CPKT_GROUP}")
  endif()
  cpkt_group_add_test(NAME ${_cpkt_runtime_policy_name}
      COMMAND bash "${CMAKE_SOURCE_DIR}/tests/local_executable_runtime_policy_test.sh"
        "${CPKT_RUNTIME_LOADER}" ${_cpkt_local_executables})
endfunction()
if(NOT CPKT_DEPENDENCY_PRODUCER)
  add_custom_target(cpkt_operation_guard
    COMMAND "${CPKT_OPERATION_PYTHON}" "${CMAKE_SOURCE_DIR}/scripts/cpkt_operation.py"
      --root "${CMAKE_SOURCE_DIR}" --group "${CPKT_GROUP}" --check
    VERBATIM)
  cmake_language(DEFER CALL cpkt_validate_owned_graph)
endif()
if(CPKT_BUILD_TESTS AND CPKT_NATIVE_BOOTLIN_RUNTIME)
  cmake_language(DEFER CALL cpkt_register_local_runtime_checks)
endif()
if(CPKT_FACADE_ONLY AND CPKT_ENABLE_FUZZING AND CPKT_GROUP STREQUAL "core")
  foreach(_cpkt_facade_only_cache_var
        CPKT_DIST_DIR
        CPKT_TARGET_ARCH
        CPKT_TARGET_LIBC
        CPKT_TARGET_OS)
    if(DEFINED ${_cpkt_facade_only_cache_var})
      set(_cpkt_facade_only_ignored "${${_cpkt_facade_only_cache_var}}")
    endif()
  endforeach()
  unset(_cpkt_facade_only_ignored)
  if(NOT CPKT_BUILD_TESTS)
    message(FATAL_ERROR "CPKT_FACADE_ONLY requires CPKT_BUILD_TESTS=ON")
  endif()
  return()
endif()
if(DEFINED CPKT_BUILD_STATIC AND NOT CPKT_BUILD_STATIC)
  message(FATAL_ERROR "cpkt release bundles always include static and shared artifacts; CPKT_BUILD_STATIC cannot be disabled.")
endif()
if(DEFINED CPKT_BUILD_SHARED AND NOT CPKT_BUILD_SHARED)
  message(FATAL_ERROR "cpkt release bundles always include static and shared artifacts; CPKT_BUILD_SHARED cannot be disabled.")
endif()
set(CPKT_BUILD_STATIC ON CACHE INTERNAL "cpkt release bundles always include static artifacts.")
set(CPKT_BUILD_SHARED ON CACHE INTERNAL "cpkt release bundles always include shared artifacts.")
set(CPKT_BUNDLE_VERSION "${PROJECT_VERSION}" CACHE STRING "Published dependency bundle version." FORCE)
set(CPKT_LIBPNG_VERSION "1.6.58" CACHE STRING "Pinned libpng release.")
set(CPKT_LIBHARU_VERSION "2.4.6" CACHE STRING "Pinned libHaru release.")
set(CPKT_MINIAUDIO_VERSION "0.11.25" CACHE STRING "Pinned miniaudio release.")
set(CPKT_WHISPER_VERSION "v1.9.4" CACHE STRING "Pinned whisper.cpp release.")
set(CPKT_OPEN62541_VERSION "1.5.8" CACHE STRING "Pinned open62541 release.")
set(CPKT_OPEN62541_PATCHSET "mqtt-prefix-packet-headers-crypto-logging-24" CACHE STRING "cpkt open62541 patchset identity." FORCE)
set(CPKT_AUDIO_ABI_VERSION "0" CACHE STRING "Audio facade ABI major. Do not bump without maintainer approval.")
set(CPKT_SUS_ABI_VERSION "0" CACHE STRING "Susurro/whisper facade ABI major. Do not bump without maintainer approval.")
set(CPKT_OPCUA_ABI_VERSION "0" CACHE STRING "OPC UA facade ABI major. Do not bump without maintainer approval.")
set(CPKT_PDF_ABI_VERSION "0" CACHE STRING "PDF facade ABI major. Do not bump without maintainer approval.")
if(NOT CPKT_SUS_CPU_ONLY)
  message(FATAL_ERROR "CPKT_SUS_CPU_ONLY=OFF is reserved for a later GPU-backend packaging phase")
endif()
set(CPKT_SUS_BACKEND_CAPABILITIES "cpu" CACHE INTERNAL "Compiled cpkt_sus whisper.cpp backend capability list.")
set(CPKT_CXX_STDLIB_STATIC_LIBRARY "" CACHE FILEPATH "Static C++ standard library archive used by C-facing static SDK metadata.")
if(CPKT_CXX_STDLIB_STATIC_LIBRARY STREQUAL "" AND CMAKE_CXX_COMPILER_ID MATCHES "^(GNU|Clang)$")
  execute_process(
      COMMAND "${CMAKE_CXX_COMPILER}" -print-file-name=libstdc++.a
      RESULT_VARIABLE _cpkt_cxx_stdlib_result
      OUTPUT_VARIABLE _cpkt_cxx_stdlib_output
      ERROR_QUIET
      OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(_cpkt_cxx_stdlib_result EQUAL 0 AND
        NOT _cpkt_cxx_stdlib_output STREQUAL "" AND
        NOT _cpkt_cxx_stdlib_output STREQUAL "libstdc++.a" AND
        EXISTS "${_cpkt_cxx_stdlib_output}")
    set(CPKT_CXX_STDLIB_STATIC_LIBRARY "${_cpkt_cxx_stdlib_output}" CACHE FILEPATH "Static C++ standard library archive used by C-facing static SDK metadata." FORCE)
  endif()
endif()
set(CPKT_CXX_LIBGCC_STATIC_LIBRARY "" CACHE FILEPATH "Static GCC runtime archive used by C-facing static SDK metadata.")
if(CPKT_CXX_LIBGCC_STATIC_LIBRARY STREQUAL "" AND CMAKE_CXX_COMPILER_ID MATCHES "^(GNU|Clang)$")
  execute_process(
      COMMAND "${CMAKE_CXX_COMPILER}" -print-libgcc-file-name
      RESULT_VARIABLE _cpkt_cxx_libgcc_result
      OUTPUT_VARIABLE _cpkt_cxx_libgcc_output
      ERROR_QUIET
      OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(_cpkt_cxx_libgcc_result EQUAL 0 AND
        NOT _cpkt_cxx_libgcc_output STREQUAL "" AND
        NOT _cpkt_cxx_libgcc_output STREQUAL "libgcc.a" AND
        EXISTS "${_cpkt_cxx_libgcc_output}")
    set(CPKT_CXX_LIBGCC_STATIC_LIBRARY "${_cpkt_cxx_libgcc_output}" CACHE FILEPATH "Static GCC runtime archive used by C-facing static SDK metadata." FORCE)
  endif()
endif()
include(cmake/CpktDependencyArchiveCache.cmake)
if(CPKT_BUILD_DEPENDENCIES OR CPKT_BUILD_TESTS)
  cpkt_initialize_dependency_cache()
endif()
set(CPKT_DEPENDENCY_CACHE_LOCK_TIMEOUT "120" CACHE STRING "Maximum shared dependency archive cache lock wait in seconds.")
set(CPKT_DOWNLOAD_ROOT "${CMAKE_SOURCE_DIR}/.cache/downloads" CACHE PATH "Local ExternalProject archive staging root.")
set(CPKT_DIST_DIR "${CMAKE_SOURCE_DIR}/dist" CACHE PATH "Output directory for package archives.")
set(CPKT_TARGET_ARCH "${CMAKE_SYSTEM_PROCESSOR}" CACHE STRING "Artifact architecture name.")
set(CPKT_TARGET_OS "${CMAKE_SYSTEM_NAME}" CACHE STRING "Artifact operating system name.")
set(CPKT_TARGET_LIBC "" CACHE STRING "Artifact libc suffix for Linux targets.")
set(CPKT_DEPENDENCY_BUILD_TYPE "Release")
set(CPKT_DEPENDENCY_BUILD_JOBS_DEFAULT 8)
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin" AND CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
  set(CPKT_DEPENDENCY_BUILD_JOBS_DEFAULT 2)
endif()
if(NOT CPKT_DEPENDENCY_BUILD_JOBS_DEFAULT OR CPKT_DEPENDENCY_BUILD_JOBS_DEFAULT LESS 1)
  set(CPKT_DEPENDENCY_BUILD_JOBS_DEFAULT 1)
endif()
set(CPKT_DEPENDENCY_BUILD_JOBS "${CPKT_DEPENDENCY_BUILD_JOBS_DEFAULT}" CACHE STRING "Parallel dependency build job count.")
set(_cpkt_job_limit 8)
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
  set(_cpkt_job_limit 2)
endif()
if(NOT CPKT_DEPENDENCY_BUILD_JOBS MATCHES "^[1-9][0-9]*$" OR
    CPKT_DEPENDENCY_BUILD_JOBS GREATER _cpkt_job_limit)
  message(FATAL_ERROR "CPKT_DEPENDENCY_BUILD_JOBS must be between 1 and ${_cpkt_job_limit} on this host")
endif()
set(CPKT_DEPENDENCY_DOWNLOAD_TIMEOUT "300" CACHE STRING "Maximum source archive download time in seconds.")
set(CPKT_DEPENDENCY_DOWNLOAD_INACTIVITY_TIMEOUT "60" CACHE STRING "Maximum source archive idle download time in seconds.")
set(CPKT_DEPENDENCY_DOWNLOAD_RETRIES "3" CACHE STRING "Bounded retry count for each dependency archive URL.")
string(TOLOWER "${CPKT_TARGET_OS}" CPKT_TARGET_OS_LOWER)
cpkt_normalize_arch("${CPKT_TARGET_ARCH}" CPKT_TARGET_ARCH_LOWER)
if(CPKT_TARGET_OS_LOWER STREQUAL "darwin" AND CPKT_TARGET_ARCH_LOWER STREQUAL "aarch64")
  set(CPKT_TARGET_ARCH_LOWER "arm64")
endif()
set(CPKT_TARGET_ARCH "${CPKT_TARGET_ARCH_LOWER}" CACHE STRING "Artifact architecture name." FORCE)
if(CPKT_TARGET_OS_LOWER STREQUAL "linux" AND NOT CPKT_TARGET_LIBC)
  execute_process(
      COMMAND "${CMAKE_C_COMPILER}" -dumpmachine
      OUTPUT_VARIABLE cpkt_compiler_machine
      RESULT_VARIABLE cpkt_compiler_machine_result
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET
    )
  if(cpkt_compiler_machine_result EQUAL 0 AND cpkt_compiler_machine MATCHES "musl")
    set(CPKT_TARGET_LIBC "musl")
  else()
    set(CPKT_TARGET_LIBC "gnu")
  endif()
endif()
if(CPKT_TARGET_OS_LOWER STREQUAL "darwin")
  set(CPKT_TARGET_ID "${CPKT_TARGET_ARCH_LOWER}-apple-darwin")
elseif(CPKT_TARGET_OS_LOWER STREQUAL "linux")
  set(CPKT_TARGET_ID "${CPKT_TARGET_ARCH_LOWER}-linux-${CPKT_TARGET_LIBC}")
else()
  set(CPKT_TARGET_ID "${CPKT_TARGET_ARCH_LOWER}-${CPKT_TARGET_OS_LOWER}")
endif()
set(CPKT_TARGET_ID "${CPKT_TARGET_ID}" CACHE INTERNAL "Resolved SDK target identity." FORCE)
set(_cpkt_default_external_root "${CMAKE_SOURCE_DIR}/.cache/deps/${CPKT_TARGET_ID}")
set(_cpkt_default_dependency_build_root "${CMAKE_SOURCE_DIR}/.cache/deps-build/${CPKT_TARGET_ID}")
set(CPKT_DEPENDENCY_CONTRACT_ROOT "${CMAKE_SOURCE_DIR}/.cache/dependency-contracts" CACHE PATH "Target-local dependency build contract metadata.")
set(_cpkt_external_root_explicit OFF)
if(DEFINED CPKT_EXTERNAL_ROOT)
  set(_cpkt_external_root_explicit ON)
  set(_cpkt_external_root_original "${CPKT_EXTERNAL_ROOT}")
endif()
set(_cpkt_dependency_build_root_explicit OFF)
if(DEFINED CPKT_DEPENDENCY_BUILD_ROOT)
  set(_cpkt_dependency_build_root_explicit ON)
  set(_cpkt_dependency_build_root_original "${CPKT_DEPENDENCY_BUILD_ROOT}")
endif()
if(DEFINED CPKT_EXTERNAL_ROOT)
  string(FIND "${CPKT_EXTERNAL_ROOT}" "${CMAKE_SOURCE_DIR}/.cache/deps/" _cpkt_external_root_under_cache)
else()
  set(_cpkt_external_root_under_cache -1)
endif()
if(NOT DEFINED CPKT_EXTERNAL_ROOT
    OR "${CPKT_EXTERNAL_ROOT}" STREQUAL "${CMAKE_SOURCE_DIR}/.cache/deps"
    OR (NOT CPKT_ALLOW_DEPENDENCY_ROOT_OVERRIDE
      AND _cpkt_external_root_under_cache EQUAL 0
      AND NOT "${CPKT_EXTERNAL_ROOT}" STREQUAL "${_cpkt_default_external_root}"))
  set(CPKT_EXTERNAL_ROOT "${_cpkt_default_external_root}" CACHE PATH "Target-local install root for dependency artifacts." FORCE)
endif()
if(_cpkt_external_root_explicit
    AND (NOT "${_cpkt_external_root_original}" STREQUAL "${CPKT_EXTERNAL_ROOT}"
      OR "${CPKT_EXTERNAL_ROOT}" STREQUAL "${_cpkt_default_external_root}"))
  set(_cpkt_external_root_explicit OFF)
endif()
if(DEFINED CPKT_DEPENDENCY_BUILD_ROOT)
  string(FIND "${CPKT_DEPENDENCY_BUILD_ROOT}" "${CMAKE_SOURCE_DIR}/.cache/deps-build/" _cpkt_dependency_build_root_under_cache)
else()
  set(_cpkt_dependency_build_root_under_cache -1)
endif()
if(NOT DEFINED CPKT_DEPENDENCY_BUILD_ROOT
    OR "${CPKT_DEPENDENCY_BUILD_ROOT}" STREQUAL "${CMAKE_SOURCE_DIR}/.cache/deps-build"
    OR (NOT CPKT_ALLOW_DEPENDENCY_ROOT_OVERRIDE
      AND _cpkt_dependency_build_root_under_cache EQUAL 0
      AND NOT "${CPKT_DEPENDENCY_BUILD_ROOT}" STREQUAL "${_cpkt_default_dependency_build_root}"))
  set(CPKT_DEPENDENCY_BUILD_ROOT "${_cpkt_default_dependency_build_root}" CACHE PATH "Target-local build root for dependency artifacts." FORCE)
endif()
if(_cpkt_dependency_build_root_explicit
    AND (NOT "${_cpkt_dependency_build_root_original}" STREQUAL "${CPKT_DEPENDENCY_BUILD_ROOT}"
      OR "${CPKT_DEPENDENCY_BUILD_ROOT}" STREQUAL "${_cpkt_default_dependency_build_root}"))
  set(_cpkt_dependency_build_root_explicit OFF)
endif()
set(CPKT_EXTERNAL_ROOT_LIFECYCLE_OWNED ON)
if(CPKT_ALLOW_DEPENDENCY_ROOT_OVERRIDE
    AND CPKT_CALLER_OWNED_DEPENDENCY_ROOTS
    AND _cpkt_external_root_explicit)
  set(CPKT_EXTERNAL_ROOT_LIFECYCLE_OWNED OFF)
endif()
set(CPKT_DEPENDENCY_BUILD_ROOT_LIFECYCLE_OWNED ON)
if(CPKT_ALLOW_DEPENDENCY_ROOT_OVERRIDE
    AND CPKT_CALLER_OWNED_DEPENDENCY_ROOTS
    AND _cpkt_dependency_build_root_explicit)
  set(CPKT_DEPENDENCY_BUILD_ROOT_LIFECYCLE_OWNED OFF)
endif()
set(_cpkt_inventory_arguments "")
if(NOT CPKT_BUILD_TESTS)
  list(APPEND _cpkt_inventory_arguments --no-tests)
endif()
execute_process(COMMAND "${CPKT_OPERATION_PYTHON}" "${CMAKE_SOURCE_DIR}/scripts/cpkt_inventory_cli.py"
  --root "${CMAKE_SOURCE_DIR}" --group "${CPKT_GROUP}" --closure --cmake ${_cpkt_inventory_arguments}
  OUTPUT_VARIABLE CPKT_ACTIVE_COMPONENTS OUTPUT_STRIP_TRAILING_WHITESPACE
  RESULT_VARIABLE _cpkt_inventory_status)
if(NOT _cpkt_inventory_status EQUAL 0)
  message(FATAL_ERROR "Invalid component inventory")
endif()
if(CPKT_GROUP MATCHES "^(db|misc)$")
  if(NOT CPKT_PREREQUISITE_CONFIGURATION)
    set(CPKT_PREREQUISITE_CONFIGURATION "${CMAKE_BUILD_TYPE}")
  endif()
  execute_process(COMMAND "${CPKT_OPERATION_PYTHON}" "${CMAKE_SOURCE_DIR}/scripts/cpkt_receipt_cli.py"
      --root "${CMAKE_SOURCE_DIR}" --group "${CPKT_GROUP}" --target "${CPKT_TARGET_ID}"
      --configuration "${CPKT_PREREQUISITE_CONFIGURATION}" --preset "$ENV{CPKT_PRESET}"
      RESULT_VARIABLE _core_status)
  if(NOT _core_status EQUAL 0)
    message(FATAL_ERROR "Core prerequisite is not development-ready")
  endif()
endif()
if(CPKT_ENABLE_FUZZING)
  if(NOT CPKT_AFLPP_ROOT)
    message(FATAL_ERROR "CPKT_ENABLE_FUZZING requires the pinned AFL++ toolchain")
  endif()
  if(NOT CMAKE_C_COMPILER MATCHES "/cpkt-afl-gcc$" OR
        NOT CMAKE_CXX_COMPILER MATCHES "/cpkt-afl-g[+][+]$")
    message(FATAL_ERROR "CPKT_ENABLE_FUZZING requires the pinned AFL++ compiler wrappers")
  endif()
endif()
include(cmake/CpktDependencies.cmake)
cpkt_configure_dependencies()
if(CPKT_DEPENDENCY_PRODUCER)
  return()
endif()
find_program(CPKT_PYTHON3_EXECUTABLE NAMES python3 REQUIRED)
set(Python3_EXECUTABLE "${CPKT_PYTHON3_EXECUTABLE}")
cpkt_group_add_library(cpkt_audio_static STATIC src/audio.c)
cpkt_configure_c89_target(cpkt_audio_static)
cpkt_group_target_command(add_dependencies cpkt_audio_static cpkt::miniaudio_static)
cpkt_add_repo_warning_errors(cpkt_audio_static)
if(UNIX)
  cpkt_group_target_command(target_compile_definitions cpkt_audio_static PRIVATE _POSIX_C_SOURCE=200809L)
endif()
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  cpkt_group_target_command(target_compile_options cpkt_audio_static PRIVATE
      -Wno-unused-function
      -ffunction-sections
      -fdata-sections)
endif()
cpkt_group_target_command(target_include_directories cpkt_audio_static
  PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/include>"
  PRIVATE
    "$<TARGET_PROPERTY:cpkt::miniaudio_static,INTERFACE_INCLUDE_DIRECTORIES>"
)
cpkt_group_target_command(target_compile_definitions cpkt_audio_static PRIVATE
  CPKT_AUDIO_NATIVE_RUNTIME_DEVICE_IO)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  cpkt_group_target_command(target_compile_definitions cpkt_audio_static PRIVATE
      CPKT_AUDIO_AUTO_PROCESS_DEVICE_IO)
endif()
cpkt_group_target_command(target_link_libraries cpkt_audio_static PUBLIC
  cpkt::curl_static
  m
  ${CMAKE_DL_LIBS}
  Threads::Threads
)
cpkt_group_set_target_properties(cpkt_audio_static PROPERTIES OUTPUT_NAME cpktaudio POSITION_INDEPENDENT_CODE ON)
cpkt_group_add_library(cpkt_audio_shared SHARED src/audio.c)
cpkt_configure_c89_target(cpkt_audio_shared)
cpkt_group_target_command(add_dependencies cpkt_audio_shared cpkt::miniaudio_shared)
cpkt_add_repo_warning_errors(cpkt_audio_shared)
if(UNIX)
  cpkt_group_target_command(target_compile_definitions cpkt_audio_shared PRIVATE _POSIX_C_SOURCE=200809L)
endif()
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  cpkt_group_target_command(target_compile_options cpkt_audio_shared PRIVATE -Wno-unused-function)
endif()
cpkt_group_target_command(target_include_directories cpkt_audio_shared
  PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/include>"
  PRIVATE
    "$<TARGET_PROPERTY:cpkt::miniaudio_shared,INTERFACE_INCLUDE_DIRECTORIES>"
)
cpkt_group_target_command(target_compile_definitions cpkt_audio_shared PRIVATE
  CPKT_AUDIO_NATIVE_RUNTIME_DEVICE_IO)
cpkt_group_target_command(target_link_libraries cpkt_audio_shared PUBLIC
  cpkt::curl_shared
  m
  ${CMAKE_DL_LIBS}
  Threads::Threads
)
cpkt_group_set_target_properties(cpkt_audio_shared PROPERTIES OUTPUT_NAME cpktaudio C_VISIBILITY_PRESET hidden POSITION_INDEPENDENT_CODE ON SOVERSION "${CPKT_AUDIO_ABI_VERSION}" VERSION "${PROJECT_VERSION}")
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  cpkt_group_set_target_properties(cpkt_audio_shared PROPERTIES INSTALL_NAME_DIR "@rpath" BUILD_RPATH "@loader_path" INSTALL_RPATH "@loader_path" BUILD_WITH_INSTALL_RPATH ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  cpkt_group_set_target_properties(cpkt_audio_shared PROPERTIES BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN" BUILD_WITH_INSTALL_RPATH ON)
endif()
cpkt_group_add_library(cpkt_sus_static STATIC src/sus.c)
cpkt_configure_c89_target(cpkt_sus_static)
cpkt_add_repo_warning_errors(cpkt_sus_static)
if(UNIX)
  cpkt_group_target_command(target_compile_definitions cpkt_sus_static PRIVATE _POSIX_C_SOURCE=200809L)
endif()
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  cpkt_group_target_command(target_compile_options cpkt_sus_static PRIVATE -Drestrict=)
endif()
cpkt_group_target_command(target_include_directories cpkt_sus_static
  PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/include>"
)
cpkt_group_target_command(target_link_libraries cpkt_sus_static PUBLIC
  cpkt_audio_static
  cpkt::whisper_static
  cpkt::curl_static
  cpkt::openssl_crypto_static
)
cpkt_group_target_command(target_compile_definitions cpkt_sus_static PRIVATE
  CPKT_SUS_FACADE_VERSION="${CPKT_SUS_ABI_VERSION}"
  CPKT_SUS_BACKEND_CAPABILITIES="${CPKT_SUS_BACKEND_CAPABILITIES}")
cpkt_group_set_target_properties(cpkt_sus_static PROPERTIES OUTPUT_NAME cpktsus POSITION_INDEPENDENT_CODE ON)
cpkt_group_add_library(cpkt_sus_shared SHARED src/sus.c)
cpkt_configure_c89_target(cpkt_sus_shared)
cpkt_add_repo_warning_errors(cpkt_sus_shared)
if(UNIX)
  cpkt_group_target_command(target_compile_definitions cpkt_sus_shared PRIVATE _POSIX_C_SOURCE=200809L)
endif()
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  cpkt_group_target_command(target_compile_options cpkt_sus_shared PRIVATE -Drestrict=)
endif()
cpkt_group_target_command(target_include_directories cpkt_sus_shared
  PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/include>"
)
cpkt_group_target_command(target_link_libraries cpkt_sus_shared PUBLIC
  cpkt_audio_shared
  cpkt::whisper_shared
  cpkt::curl_shared
  cpkt::openssl_crypto_shared
)
cpkt_group_target_command(target_compile_definitions cpkt_sus_shared PRIVATE
  CPKT_SUS_FACADE_VERSION="${CPKT_SUS_ABI_VERSION}"
  CPKT_SUS_BACKEND_CAPABILITIES="${CPKT_SUS_BACKEND_CAPABILITIES}")
cpkt_group_set_target_properties(cpkt_sus_shared PROPERTIES OUTPUT_NAME cpktsus POSITION_INDEPENDENT_CODE ON SOVERSION "${CPKT_SUS_ABI_VERSION}" VERSION "${PROJECT_VERSION}")
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  cpkt_group_set_target_properties(cpkt_sus_shared PROPERTIES INSTALL_NAME_DIR "@rpath" BUILD_RPATH "@loader_path" INSTALL_RPATH "@loader_path" BUILD_WITH_INSTALL_RPATH ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  cpkt_group_set_target_properties(cpkt_sus_shared PROPERTIES BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN" BUILD_WITH_INSTALL_RPATH ON)
endif()
if(CPKT_CAN_RUN_TARGET_EXECUTABLES)
  cpkt_group_add_executable(cpktxscribe tools/cpktxscribe.c)
  cpkt_group_use_local_runtime(cpktxscribe)
  cpkt_group_target_command(target_compile_options cpktxscribe PRIVATE -std=c89)
  if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    cpkt_group_target_command(target_compile_options cpktxscribe PRIVATE
          -Wall
          -Wextra
          -Wpedantic
          -Werror
          "-ffile-prefix-map=${CMAKE_SOURCE_DIR}=src"
          "-ffile-prefix-map=${CMAKE_BINARY_DIR}=build"
          "-fdebug-prefix-map=${CMAKE_SOURCE_DIR}=src"
          "-fdebug-prefix-map=${CMAKE_BINARY_DIR}=build")
  elseif(MSVC)
    cpkt_group_target_command(target_compile_options cpktxscribe PRIVATE /W4 /WX)
  endif()
  cpkt_group_target_command(target_link_libraries cpktxscribe PRIVATE cpkt_sus_static)
  cpkt_group_set_target_properties(cpktxscribe PROPERTIES LINKER_LANGUAGE CXX RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools")
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    cpkt_group_target_command(target_link_options cpktxscribe PRIVATE -Wl,--gc-sections)
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
      cpkt_group_target_command(target_link_options cpktxscribe PRIVATE -static-libstdc++ -static-libgcc)
    endif()
  endif()
  if(CPKT_BUILD_TESTS)
    cpkt_group_add_test(
          NAME cpktxscribe_cache_status
          COMMAND ${CMAKE_SOURCE_DIR}/tests/cpktxscribe_cache_status_test.sh
            ${CPKT_TEST_EXECUTABLE_PREFIX}
            $<TARGET_FILE:cpktxscribe>)
    cpkt_group_add_test(
          NAME cpktxscribe_link_policy
          COMMAND sh ${CMAKE_SOURCE_DIR}/tests/cpktxscribe_link_policy_test.sh
            $<TARGET_FILE:cpktxscribe>)
  endif()
endif()
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(CPKT_OPCUA_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated/opcua")
add_custom_command(
  OUTPUT "${CPKT_OPCUA_GENERATED_DIR}/cpkt/opcua_types.h"
         "${CPKT_OPCUA_GENERATED_DIR}/cpkt/opcua_constants.h"
         "${CPKT_OPCUA_GENERATED_DIR}/cpkt/opcua_plugins.h"
         "${CPKT_OPCUA_GENERATED_DIR}/opcua_plugins_metadata.inc"
         "${CPKT_OPCUA_GENERATED_DIR}/opcua_types_metadata.inc"
         "${CPKT_OPCUA_GENERATED_DIR}/opcua_message_metadata.inc"
         "${CPKT_OPCUA_GENERATED_DIR}/opcua_codec_metadata.inc"
         "${CPKT_OPCUA_GENERATED_DIR}/opcua_eventloop_metadata.inc"
         "${CPKT_OPCUA_GENERATED_DIR}/opcua_config_metadata.inc"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_config_plugins_metadata.inc"
         "${CPKT_OPCUA_GENERATED_DIR}/opcua_nodestore_metadata.inc"
         "${CPKT_OPCUA_GENERATED_DIR}/opcua_native_format.c"
         "${CPKT_OPCUA_GENERATED_DIR}/opcua_native_nodestore.h"
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tools/opcua/generate.py"
    --upstream "${CPKT_EXTERNAL_ROOT}/open62541/install/share/open62541"
    --output "${CPKT_OPCUA_GENERATED_DIR}"
  DEPENDS cpkt::open62541_static
    "${CMAKE_SOURCE_DIR}/tools/opcua/generate.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/c89_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/plugin_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/history_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/server_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/node_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/producer_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/creation_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/client_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/async_client_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/core_client_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/value_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/certificate_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/utility_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/format_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/security_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/policy_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/pubsub_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/codec_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/event_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/dynamic_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/eventloop_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/config_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/config_plugin_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/config_server_plugin_emitter.py"
    "${CMAKE_SOURCE_DIR}/tools/opcua/nodestore_emitter.py"
  VERBATIM)
cpkt_group_add_custom_target(cpkt_opcua_types_generate DEPENDS
  "${CPKT_OPCUA_GENERATED_DIR}/cpkt/opcua_types.h"
  "${CPKT_OPCUA_GENERATED_DIR}/cpkt/opcua_constants.h"
  "${CPKT_OPCUA_GENERATED_DIR}/cpkt/opcua_plugins.h"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_plugins_metadata.inc"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_types_metadata.inc"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_message_metadata.inc"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_codec_metadata.inc"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_eventloop_metadata.inc"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_config_metadata.inc"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_config_plugins_metadata.inc"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_nodestore_metadata.inc"
  "${CPKT_OPCUA_GENERATED_DIR}/opcua_native_nodestore.h")
set(_cpkt_opcua_public_api_command "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tools/opcua/public_api.py" --compiler "${CMAKE_C_COMPILER}" --platform "${CPKT_TARGET_OS}" --native-include "${CPKT_EXTERNAL_ROOT}/open62541/install/include" --facade-include "${CMAKE_SOURCE_DIR}/include" --generated-include "${CPKT_OPCUA_GENERATED_DIR}" --contract "${CMAKE_SOURCE_DIR}/tools/opcua/public_api_contract.json" --report "${CMAKE_CURRENT_BINARY_DIR}/opcua-public-api-coverage.json")
cpkt_group_add_custom_target(cpkt_opcua_public_api_complete
  COMMAND ${_cpkt_opcua_public_api_command} --require-complete
  DEPENDS cpkt_opcua_types_generate VERBATIM)
set_source_files_properties("${CPKT_OPCUA_GENERATED_DIR}/opcua_native_format.c" PROPERTIES COMPILE_OPTIONS "-std=c99")
set(CPKT_OPCUA_SOURCES src/opcua.c src/opcua_arrays.c src/opcua_browse.c src/opcua_client.c src/opcua_client_async.c src/opcua_client_attributes.c src/opcua_client_nodes.c src/opcua_client_values.c src/opcua_events.c src/opcua_files.c src/opcua_history.c src/opcua_identifiers.c src/opcua_logging.c src/opcua_methods.c src/opcua_pubsub.c src/opcua_server.c src/opcua_server_attributes.c src/opcua_server_nodes.c src/opcua_server_values.c src/opcua_subscriptions.c src/opcua_types.c src/opcua_value.c)
cpkt_group_add_library(cpkt_opcua_static STATIC ${CPKT_OPCUA_SOURCES})
cpkt_configure_c89_target(cpkt_opcua_static)
cpkt_group_target_command(target_sources cpkt_opcua_static PRIVATE "${CPKT_OPCUA_GENERATED_DIR}/opcua_native_format.c")
cpkt_group_target_command(add_dependencies cpkt_opcua_static cpkt_opcua_types_generate)
cpkt_add_repo_warning_errors(cpkt_opcua_static)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  cpkt_group_target_command(target_compile_options cpkt_opcua_static PRIVATE -Dinline=)
endif()
cpkt_group_target_command(target_include_directories cpkt_opcua_static
  PUBLIC
    "$<BUILD_INTERFACE:${CPKT_OPCUA_GENERATED_DIR}>"
    "$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/include>"
)
cpkt_group_target_command(target_link_libraries cpkt_opcua_static PUBLIC cpkt::open62541_static Threads::Threads)
cpkt_group_target_command(target_compile_definitions cpkt_opcua_static PRIVATE CPKT_OPCUA_FACADE_VERSION="${CPKT_OPCUA_ABI_VERSION}")
cpkt_group_set_target_properties(cpkt_opcua_static PROPERTIES OUTPUT_NAME cpkt_opcua POSITION_INDEPENDENT_CODE ON)
cpkt_group_add_library(cpkt_opcua_shared SHARED ${CPKT_OPCUA_SOURCES})
cpkt_configure_c89_target(cpkt_opcua_shared)
cpkt_group_target_command(target_sources cpkt_opcua_shared PRIVATE "${CPKT_OPCUA_GENERATED_DIR}/opcua_native_format.c")
cpkt_group_target_command(add_dependencies cpkt_opcua_shared cpkt_opcua_types_generate)
cpkt_add_repo_warning_errors(cpkt_opcua_shared)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  cpkt_group_target_command(target_compile_options cpkt_opcua_shared PRIVATE -Dinline=)
endif()
cpkt_group_target_command(target_include_directories cpkt_opcua_shared
  PUBLIC
    "$<BUILD_INTERFACE:${CPKT_OPCUA_GENERATED_DIR}>"
    "$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/include>"
)
cpkt_group_target_command(target_link_libraries cpkt_opcua_shared PUBLIC cpkt::open62541_shared Threads::Threads)
cpkt_group_target_command(target_compile_definitions cpkt_opcua_shared PRIVATE CPKT_OPCUA_FACADE_VERSION="${CPKT_OPCUA_ABI_VERSION}")
cpkt_group_set_target_properties(cpkt_opcua_shared PROPERTIES OUTPUT_NAME cpkt_opcua POSITION_INDEPENDENT_CODE ON SOVERSION "${CPKT_OPCUA_ABI_VERSION}" VERSION "${PROJECT_VERSION}")
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  cpkt_group_set_target_properties(cpkt_opcua_shared PROPERTIES INSTALL_NAME_DIR "@rpath" BUILD_RPATH "@loader_path" INSTALL_RPATH "@loader_path" BUILD_WITH_INSTALL_RPATH ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  cpkt_group_set_target_properties(cpkt_opcua_shared PROPERTIES BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN" BUILD_WITH_INSTALL_RPATH ON)
endif()
cpkt_group_add_library(cpkt_pdf_static STATIC src/pdf.c)
cpkt_configure_c89_target(cpkt_pdf_static)
cpkt_add_repo_warning_errors(cpkt_pdf_static)
cpkt_group_target_command(target_include_directories cpkt_pdf_static PUBLIC "$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/include>")
cpkt_group_target_command(target_link_libraries cpkt_pdf_static PUBLIC cpkt::haru_static)
cpkt_group_set_target_properties(cpkt_pdf_static PROPERTIES OUTPUT_NAME cpkt_pdf POSITION_INDEPENDENT_CODE ON)
cpkt_group_add_library(cpkt_pdf_shared SHARED src/pdf.c)
cpkt_configure_c89_target(cpkt_pdf_shared)
cpkt_add_repo_warning_errors(cpkt_pdf_shared)
cpkt_group_target_command(target_include_directories cpkt_pdf_shared PUBLIC "$<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/include>")
cpkt_group_target_command(target_link_libraries cpkt_pdf_shared PUBLIC cpkt::haru_shared)
cpkt_group_set_target_properties(cpkt_pdf_shared PROPERTIES OUTPUT_NAME cpkt_pdf C_VISIBILITY_PRESET hidden POSITION_INDEPENDENT_CODE ON SOVERSION "${CPKT_PDF_ABI_VERSION}" VERSION "${PROJECT_VERSION}")
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  cpkt_group_set_target_properties(cpkt_pdf_shared PROPERTIES INSTALL_NAME_DIR "@rpath" BUILD_RPATH "@loader_path" INSTALL_RPATH "@loader_path" BUILD_WITH_INSTALL_RPATH ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  cpkt_group_set_target_properties(cpkt_pdf_shared PROPERTIES BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN" BUILD_WITH_INSTALL_RPATH ON)
endif()
if(CPKT_BUILD_TESTS)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    cpkt_group_add_test(NAME sdk_runtime_loader
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/sdk_runtime_loader_test.py"
          --scratch "${CMAKE_BINARY_DIR}" --target "${CPKT_TARGET_ID}"
          --compiler "${CMAKE_C_COMPILER}" --readelf "${CMAKE_READELF}"
          --sysroot "${CMAKE_SYSROOT}")
    cpkt_group_set_tests_properties(sdk_runtime_loader PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
  endif()
  cpkt_group_add_test(NAME package_isolation_build
      COMMAND "${CPKT_OPERATION_PYTHON}" "${CMAKE_SOURCE_DIR}/tests/package_isolation_build_test.py")
  cpkt_group_add_test(NAME package_producer_reuse
      COMMAND "${CPKT_OPERATION_PYTHON}" "${CMAKE_SOURCE_DIR}/tests/package_producer_reuse_test.py")
  cpkt_group_add_test(NAME selected_test_executables
      COMMAND "${Python3_EXECUTABLE}"
        "${CMAKE_SOURCE_DIR}/tests/selected_test_executables_test.py"
        "${CMAKE_SOURCE_DIR}")
  cpkt_group_set_tests_properties(selected_test_executables PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
  include(cmake/CpktTestPslog.cmake)
  if(CPKT_SELECT_core OR CPKT_SELECT_misc)
    cpkt_add_test_pslog()
  endif()
  foreach(_cpkt_opcua_logging_linkage IN ITEMS static shared)
    cpkt_group_add_executable(cpkt_opcua_logging_${_cpkt_opcua_logging_linkage}_test
          tests/opcua_logging_test.c tests/opcua_logging_native_peer.c)
    cpkt_group_use_local_runtime(cpkt_opcua_logging_${_cpkt_opcua_logging_linkage}_test
          cpkt::open62541_shared cpkt::openssl_ssl_shared cpkt::openssl_crypto_shared)
    set_source_files_properties(tests/opcua_logging_test.c PROPERTIES COMPILE_OPTIONS "-std=c89;-pedantic-errors")
    set_source_files_properties(tests/opcua_logging_native_peer.c PROPERTIES COMPILE_OPTIONS "-std=c99")
    cpkt_add_repo_warning_errors(cpkt_opcua_logging_${_cpkt_opcua_logging_linkage}_test)
    cpkt_group_target_command(target_link_libraries cpkt_opcua_logging_${_cpkt_opcua_logging_linkage}_test
          PRIVATE cpkt_opcua_${_cpkt_opcua_logging_linkage} cpkt_test_pslog)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND _cpkt_opcua_logging_linkage STREQUAL "static")
      cpkt_group_target_command(target_sources cpkt_opcua_logging_static_test PRIVATE
              tests/opcua_logging_alloc_failure.c)
      cpkt_group_target_command(target_compile_definitions cpkt_opcua_logging_static_test PRIVATE
              CPKT_LOGGING_ALLOC_FAILURE_TEST=1)
      cpkt_group_target_command(target_link_options cpkt_opcua_logging_static_test PRIVATE
              -Wl,--wrap=calloc -Wl,--wrap=EVP_KDF_derive)
    endif()
    if(CPKT_CAN_RUN_TARGET_EXECUTABLES)
      cpkt_group_add_test(NAME opcua_logging_${_cpkt_opcua_logging_linkage}
              COMMAND cpkt_opcua_logging_${_cpkt_opcua_logging_linkage}_test
                "${CMAKE_BINARY_DIR}/opcua-logging-${_cpkt_opcua_logging_linkage}.json5")
      cpkt_group_set_tests_properties(opcua_logging_${_cpkt_opcua_logging_linkage} PROPERTIES LABELS "facade;memcheck;integration;offline;opcua" TIMEOUT 90)
      cpkt_group_add_test(NAME opcua_logging_${_cpkt_opcua_logging_linkage}_late_attach
              COMMAND cpkt_opcua_logging_${_cpkt_opcua_logging_linkage}_test
                "${CMAKE_BINARY_DIR}/opcua-logging-${_cpkt_opcua_logging_linkage}-late.json5"
                legacy)
      cpkt_group_set_tests_properties(opcua_logging_${_cpkt_opcua_logging_linkage}_late_attach PROPERTIES LABELS "facade;memcheck;integration;offline;opcua" TIMEOUT 90)
      cpkt_group_add_test(NAME opcua_logging_${_cpkt_opcua_logging_linkage}_output
              COMMAND "${CPKT_PYTHON3_EXECUTABLE}"
                "${CMAKE_SOURCE_DIR}/tests/opcua_logging_output_test.py"
                ${CPKT_TEST_EXECUTABLE_PREFIX}
                "$<TARGET_FILE:cpkt_opcua_logging_${_cpkt_opcua_logging_linkage}_test>"
                "${CMAKE_BINARY_DIR}/opcua-logging-${_cpkt_opcua_logging_linkage}-output.json5")
      cpkt_group_set_tests_properties(opcua_logging_${_cpkt_opcua_logging_linkage}_output PROPERTIES LABELS "integration;offline;opcua" TIMEOUT 30)
    endif()
  endforeach()
  cpkt_group_add_test(NAME opcua_logging_sdk_isolation
      COMMAND "${CMAKE_COMMAND}" "-DCPKT_NM=${CMAKE_NM}"
        "-DCPKT_STATIC=$<TARGET_FILE:cpkt_opcua_static>"
        "-DCPKT_SHARED=$<TARGET_FILE:cpkt_opcua_shared>"
        -P "${CMAKE_SOURCE_DIR}/tests/opcua_logging_sdk_isolation_test.cmake")
  cpkt_group_set_tests_properties(opcua_logging_sdk_isolation PROPERTIES LABELS "packaging;opcua")
  cpkt_group_add_executable(cpkt_opcua_c89_example examples/opcua-c89/main.c)
  cpkt_group_use_local_runtime(cpkt_opcua_c89_example)
  cpkt_group_target_command(target_compile_options cpkt_opcua_c89_example PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_opcua_c89_example)
  cpkt_group_target_command(target_link_libraries cpkt_opcua_c89_example PRIVATE cpkt_opcua_static)
  cpkt_group_add_executable(cpkt_audio_sus_c89_example examples/audio-sus-c89/main.c)
  cpkt_group_use_local_runtime(cpkt_audio_sus_c89_example)
  cpkt_group_target_command(target_compile_options cpkt_audio_sus_c89_example PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_audio_sus_c89_example)
  cpkt_group_target_command(target_link_libraries cpkt_audio_sus_c89_example PRIVATE
      cpkt_audio_static
      cpkt_sus_shared)
  cpkt_group_add_executable(cpkt_audio_vox_intro_c89_example
      examples/audio-vox-intro-c89/main.c)
  cpkt_group_use_local_runtime(cpkt_audio_vox_intro_c89_example)
  cpkt_group_target_command(target_compile_options cpkt_audio_vox_intro_c89_example PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_audio_vox_intro_c89_example)
  cpkt_group_target_command(target_link_libraries cpkt_audio_vox_intro_c89_example PRIVATE
      cpkt_audio_static)
  cpkt_group_add_executable(cpkt_audio_live_vox_c89_example
      examples/audio-live-vox-c89/main.c)
  cpkt_group_use_local_runtime(cpkt_audio_live_vox_c89_example)
  cpkt_group_target_command(target_compile_options cpkt_audio_live_vox_c89_example PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_audio_live_vox_c89_example)
  cpkt_group_target_command(target_link_libraries cpkt_audio_live_vox_c89_example PRIVATE
      cpkt_audio_shared)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CPKT_TARGET_LIBC STREQUAL "musl")
    cpkt_group_add_executable(cpkt_audio_live_vox_static_c89_example
          examples/audio-live-vox-c89/main.c)
    cpkt_group_use_local_runtime(cpkt_audio_live_vox_static_c89_example)
    cpkt_group_target_command(target_compile_options cpkt_audio_live_vox_static_c89_example PRIVATE
          -std=c89)
    cpkt_add_repo_warning_errors(cpkt_audio_live_vox_static_c89_example)
    cpkt_group_target_command(target_link_libraries cpkt_audio_live_vox_static_c89_example PRIVATE
          cpkt_audio_static)
    cpkt_group_target_command(target_link_options cpkt_audio_live_vox_static_c89_example PRIVATE
          -static -Wl,--gc-sections)
  else()
    file(REMOVE
          "${CMAKE_CURRENT_BINARY_DIR}/cpkt_audio_live_vox_static_c89_example${CMAKE_EXECUTABLE_SUFFIX}")
  endif()
  cpkt_group_add_executable(cpkt_sus_vox_intro_c89_example
      examples/sus-vox-intro-c89/main.c)
  cpkt_group_use_local_runtime(cpkt_sus_vox_intro_c89_example)
  cpkt_group_target_command(target_compile_options cpkt_sus_vox_intro_c89_example PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_sus_vox_intro_c89_example)
  cpkt_group_target_command(target_link_libraries cpkt_sus_vox_intro_c89_example PRIVATE
      cpkt_audio_static
      cpkt_sus_shared)
  cpkt_group_add_executable(cpkt_sus_live_vox_c89_example
      examples/sus-live-vox-c89/main.c)
  cpkt_group_use_local_runtime(cpkt_sus_live_vox_c89_example)
  cpkt_group_target_command(target_compile_options cpkt_sus_live_vox_c89_example PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_sus_live_vox_c89_example)
  cpkt_group_target_command(target_link_libraries cpkt_sus_live_vox_c89_example PRIVATE
      cpkt_audio_shared
      cpkt_sus_shared)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CPKT_TARGET_LIBC STREQUAL "musl")
    cpkt_group_add_executable(cpkt_sus_live_vox_static_c89_example
          examples/sus-live-vox-c89/main.c)
    cpkt_group_use_local_runtime(cpkt_sus_live_vox_static_c89_example)
    cpkt_group_target_command(target_compile_options cpkt_sus_live_vox_static_c89_example PRIVATE
          -std=c89)
    cpkt_add_repo_warning_errors(cpkt_sus_live_vox_static_c89_example)
    cpkt_group_set_target_properties(cpkt_sus_live_vox_static_c89_example PROPERTIES LINKER_LANGUAGE CXX)
    cpkt_group_target_command(target_link_libraries cpkt_sus_live_vox_static_c89_example PRIVATE
          cpkt_audio_static
          cpkt_sus_static)
    cpkt_group_target_command(target_link_options cpkt_sus_live_vox_static_c89_example PRIVATE
          -static -Wl,--gc-sections)
  else()
    file(REMOVE
          "${CMAKE_CURRENT_BINARY_DIR}/cpkt_sus_live_vox_static_c89_example${CMAKE_EXECUTABLE_SUFFIX}")
  endif()
  cpkt_group_add_executable(cpkt_abi_smoke_shared examples/abi_smoke.c)
  cpkt_group_use_local_runtime(cpkt_abi_smoke_shared)
  cpkt_group_target_command(target_compile_options cpkt_abi_smoke_shared PRIVATE -std=c99)
  cpkt_group_target_command(target_link_libraries cpkt_abi_smoke_shared PRIVATE
      cpkt::curl_shared
      cpkt::libxml2_shared
      cpkt::lua_shared
      cpkt::miniaudio_shared
      cpkt::open62541_shared
    )
  cpkt_group_add_executable(cpkt_abi_smoke_static examples/abi_smoke.c)
  cpkt_group_use_local_runtime(cpkt_abi_smoke_static)
  cpkt_group_target_command(target_compile_options cpkt_abi_smoke_static PRIVATE -std=c99)
  cpkt_group_target_command(target_link_libraries cpkt_abi_smoke_static PRIVATE
      cpkt::curl_static
      cpkt::libxml2_static
      cpkt::lua_static
      cpkt::miniaudio_static
      cpkt::open62541_static
    )
  cpkt_group_add_executable(cpkt_whisper_smoke_shared examples/whisper_smoke.c)
  cpkt_group_use_local_runtime(cpkt_whisper_smoke_shared)
  cpkt_group_target_command(target_compile_options cpkt_whisper_smoke_shared PRIVATE -std=c99)
  cpkt_group_target_command(target_link_libraries cpkt_whisper_smoke_shared PRIVATE cpkt::whisper_shared)







  if(CPKT_CAN_RUN_TARGET_EXECUTABLES)
    foreach(_cpkt_vfs_case IN ITEMS borrowed-file provider-identity)
      string(REPLACE "-" "_" _cpkt_vfs_test_name "${_cpkt_vfs_case}")
    endforeach()
  endif()
  if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    cpkt_group_set_target_properties(cpkt_abi_smoke_shared PROPERTIES BUILD_RPATH "@executable_path/../lib" INSTALL_RPATH "@executable_path/../lib" BUILD_WITH_INSTALL_RPATH ON)
  else()
    cpkt_group_add_executable(cpkt_abi_test_shared tests/abi_smoke_test.c)
    cpkt_group_use_local_runtime(cpkt_abi_test_shared)
    cpkt_group_target_command(target_link_libraries cpkt_abi_test_shared PRIVATE
          cpkt::curl_shared
          cpkt::libxml2_shared
          cpkt::lua_shared
          cpkt::miniaudio_shared
          cpkt::open62541_shared
          cpkt::cmocka
        )
    cpkt_group_add_executable(cpkt_abi_test_static tests/abi_smoke_test.c)
    cpkt_group_use_local_runtime(cpkt_abi_test_static)
    cpkt_group_target_command(target_link_libraries cpkt_abi_test_static PRIVATE
          cpkt::curl_static
          cpkt::libxml2_static
          cpkt::lua_static
          cpkt::miniaudio_static
          cpkt::open62541_static
          cpkt::cmocka
        )
    cpkt_group_add_executable(cpkt_audio_facade_test tests/audio_facade_test.c)
    cpkt_group_use_local_runtime(cpkt_audio_facade_test)
    cpkt_group_target_command(target_compile_options cpkt_audio_facade_test PRIVATE -std=c99)
    cpkt_add_repo_warning_errors(cpkt_audio_facade_test)
    cpkt_group_target_command(target_link_libraries cpkt_audio_facade_test PRIVATE
          cpkt_audio_static
          cpkt::cmocka
        )
    cpkt_group_add_executable(cpkt_audio_process_capture_probe
          tests/audio_process_capture_probe.c)
    cpkt_group_use_local_runtime(cpkt_audio_process_capture_probe)
    cpkt_group_target_command(target_compile_options cpkt_audio_process_capture_probe PRIVATE -std=c99)
    cpkt_add_repo_warning_errors(cpkt_audio_process_capture_probe)
    cpkt_group_target_command(target_link_libraries cpkt_audio_process_capture_probe PRIVATE
          cpkt_audio_static)
    cpkt_group_add_executable(cpkt_audio_process_playback_probe
          tests/audio_process_playback_probe.c)
    cpkt_group_use_local_runtime(cpkt_audio_process_playback_probe)
    cpkt_group_target_command(target_compile_options cpkt_audio_process_playback_probe PRIVATE -std=c99)
    cpkt_add_repo_warning_errors(cpkt_audio_process_playback_probe)
    cpkt_group_target_command(target_link_libraries cpkt_audio_process_playback_probe PRIVATE
          cpkt_audio_static)
    cpkt_group_add_executable(cpkt_sus_facade_test tests/sus_facade_test.c)
    cpkt_group_use_local_runtime(cpkt_sus_facade_test)
    cpkt_group_target_command(target_compile_options cpkt_sus_facade_test PRIVATE -std=c99)
    cpkt_add_repo_warning_errors(cpkt_sus_facade_test)
    cpkt_group_target_command(target_link_libraries cpkt_sus_facade_test PRIVATE
          cpkt_sus_shared
          cpkt::cmocka
        )
    cpkt_group_add_executable(cpkt_sus_audio_integration_test
          tests/sus_audio_integration_test.c)
    cpkt_group_use_local_runtime(cpkt_sus_audio_integration_test)
    cpkt_group_target_command(target_compile_options cpkt_sus_audio_integration_test PRIVATE -std=c99)
    cpkt_add_repo_warning_errors(cpkt_sus_audio_integration_test)
    cpkt_group_target_command(target_link_libraries cpkt_sus_audio_integration_test PRIVATE
          cpkt_audio_static
          cpkt_sus_shared
        )
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
      set(_cpkt_postgresql_oauth_staging_paths)
      foreach(_cpkt_postgresql_oauth_dependency IN ITEMS
                cpkt::curl_shared cpkt::zlib_shared cpkt::openssl_ssl_shared
                cpkt::libssh2_shared cpkt::nghttp2_shared cpkt::gssapi_krb5_shared
                cpkt::openldap_shared cpkt::cyrus_sasl_shared)
        cpkt_group_get_target_property(_cpkt_postgresql_oauth_dependency_location
                  ${_cpkt_postgresql_oauth_dependency} IMPORTED_LOCATION)
        get_filename_component(_cpkt_postgresql_oauth_dependency_dir
                  "${_cpkt_postgresql_oauth_dependency_location}" DIRECTORY)
        list(APPEND _cpkt_postgresql_oauth_staging_paths
                  "${_cpkt_postgresql_oauth_dependency_dir}")
      endforeach()
      list(JOIN _cpkt_postgresql_oauth_staging_paths ":"
              _cpkt_postgresql_oauth_staging_rpath)
    endif()
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
      if(CPKT_TARGET_ID STREQUAL "armhf-linux-musl")
      else()
      endif()
    endif()
    cpkt_group_get_target_property(cpkt_sasl_native_include_dir cpkt::cyrus_sasl_static
          INTERFACE_INCLUDE_DIRECTORIES)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    endif()
    cpkt_group_add_executable(cpkt_pdf_facade_static_test tests/pdf_facade_test.c)
    cpkt_group_use_local_runtime(cpkt_pdf_facade_static_test)
    cpkt_group_target_command(target_compile_options cpkt_pdf_facade_static_test PRIVATE -std=c89)
    cpkt_add_repo_warning_errors(cpkt_pdf_facade_static_test)
    cpkt_group_target_command(target_link_libraries cpkt_pdf_facade_static_test PRIVATE cpkt_pdf_static cpkt::png_static)
    cpkt_group_add_executable(cpkt_pdf_facade_shared_test tests/pdf_facade_test.c)
    cpkt_group_use_local_runtime(cpkt_pdf_facade_shared_test)
    cpkt_group_target_command(target_compile_options cpkt_pdf_facade_shared_test PRIVATE -std=c89)
    cpkt_add_repo_warning_errors(cpkt_pdf_facade_shared_test)
    cpkt_group_target_command(target_link_libraries cpkt_pdf_facade_shared_test PRIVATE cpkt_pdf_shared cpkt::png_shared)
    cpkt_group_add_executable(cpkt_opcua_facade_test
          tests/opcua_facade_test.c
          tests/opcua_c89_boundary_peer.c)
    cpkt_group_use_local_runtime(cpkt_opcua_facade_test)
    cpkt_add_repo_warning_errors(cpkt_opcua_facade_test)
    set_source_files_properties(tests/opcua_facade_test.c PROPERTIES COMPILE_OPTIONS "-std=c99")
    set_source_files_properties(tests/opcua_c89_boundary_peer.c PROPERTIES COMPILE_OPTIONS "-std=c89")
    cpkt_group_target_command(target_link_libraries cpkt_opcua_facade_test PRIVATE
          cpkt_opcua_static
          cpkt::open62541_static
          cpkt::cmocka
          Threads::Threads
        )
  endif()
  cpkt_group_add_test(NAME opcua_types_generator
      COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/opcua_types_generator_test.py"
        "${CMAKE_SOURCE_DIR}" "${CPKT_EXTERNAL_ROOT}/open62541/install/share/open62541"
        "${CMAKE_CURRENT_BINARY_DIR}")
  cpkt_group_set_tests_properties(opcua_types_generator PROPERTIES LABELS "opcua;packaging")
  cpkt_group_add_test(NAME opcua_public_api_contract
      COMMAND ${_cpkt_opcua_public_api_command} --require-complete)
  cpkt_group_add_test(NAME opcua_public_api_contract_failures
      COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/opcua_public_api_test.py"
        "${CMAKE_SOURCE_DIR}" "${CMAKE_C_COMPILER}" "${CPKT_TARGET_OS}"
        "${CMAKE_CURRENT_BINARY_DIR}")
  cpkt_group_set_tests_properties(opcua_public_api_contract opcua_public_api_contract_failures PROPERTIES LABELS "opcua;packaging")
  if(CPKT_BUILD_DEPENDENCIES)
    cpkt_group_add_test(NAME open62541_openssl_provenance
          COMMAND "${CMAKE_COMMAND}"
            "-DCPKT_OPEN62541_BUILD_ROOT=${CPKT_DEPENDENCY_BUILD_ROOT}/open62541"
            "-DCPKT_OPENSSL_PREFIX=${CPKT_EXTERNAL_ROOT}/openssl/install"
            "-DCPKT_SHARED_LIBRARY_SUFFIX=${CMAKE_SHARED_LIBRARY_SUFFIX}"
            -P "${CMAKE_SOURCE_DIR}/tests/open62541_openssl_provenance_test.cmake")
    cpkt_group_set_tests_properties(open62541_openssl_provenance PROPERTIES LABELS "packaging;opcua" TIMEOUT 30)
  endif()
  foreach(_cpkt_stdout_linkage IN ITEMS static shared)
    cpkt_group_add_executable(cpkt_opcua_stdout_${_cpkt_stdout_linkage}_test
          tests/opcua_stdout_contention_test.c)
    cpkt_group_use_local_runtime(cpkt_opcua_stdout_${_cpkt_stdout_linkage}_test
          cpkt::open62541_shared cpkt::openssl_ssl_shared cpkt::openssl_crypto_shared)
    cpkt_add_repo_warning_errors(cpkt_opcua_stdout_${_cpkt_stdout_linkage}_test)
    cpkt_group_target_command(target_compile_options cpkt_opcua_stdout_${_cpkt_stdout_linkage}_test PRIVATE -std=c99)
    cpkt_group_target_command(target_link_libraries cpkt_opcua_stdout_${_cpkt_stdout_linkage}_test PRIVATE
          cpkt::open62541_${_cpkt_stdout_linkage} Threads::Threads)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND _cpkt_stdout_linkage STREQUAL "static")
      cpkt_group_target_command(target_compile_definitions cpkt_opcua_stdout_static_test PRIVATE CPKT_TEST_STDOUT_LOCK_WRAP)
      cpkt_group_target_command(target_link_options cpkt_opcua_stdout_static_test PRIVATE -Wl,--wrap=printf,--wrap=flockfile)
    endif()
    if(CPKT_CAN_RUN_TARGET_EXECUTABLES)
      cpkt_group_add_test(NAME opcua_stdout_contention_${_cpkt_stdout_linkage}
              COMMAND cpkt_opcua_stdout_${_cpkt_stdout_linkage}_test
                "${CMAKE_CURRENT_BINARY_DIR}/opcua-stdout-${_cpkt_stdout_linkage}.log")
      cpkt_group_set_tests_properties(opcua_stdout_contention_${_cpkt_stdout_linkage} PROPERTIES LABELS "facade;opcua;memcheck" TIMEOUT 10)
    endif()
  endforeach()
  set(_cpkt_fixture_dir "${CMAKE_CURRENT_BINARY_DIR}/generated/opcua-fixture")
  add_custom_command(
      OUTPUT "${_cpkt_fixture_dir}/cpkt/opcua_types.h"
        "${_cpkt_fixture_dir}/cpkt/opcua_constants.h"
        "${_cpkt_fixture_dir}/cpkt/opcua_plugins.h"
        "${_cpkt_fixture_dir}/opcua_plugins_metadata.inc"
        "${_cpkt_fixture_dir}/opcua_types_metadata.inc"
        "${_cpkt_fixture_dir}/opcua_config_metadata.inc"
    "${_cpkt_fixture_dir}/opcua_config_plugins_metadata.inc"
    "${_cpkt_fixture_dir}/opcua_nodestore_metadata.inc"
    "${_cpkt_fixture_dir}/opcua_native_format.c"
    "${_cpkt_fixture_dir}/opcua_native_nodestore.h"
        "${_cpkt_fixture_dir}/native/open62541/types_generated.c"
        "${_cpkt_fixture_dir}/native/open62541/types_generated.h"
      COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tools/opcua/generate.py"
        --upstream "${CPKT_EXTERNAL_ROOT}/open62541/install/share/open62541"
        --output "${_cpkt_fixture_dir}"
        --extra-bsd "${CMAKE_SOURCE_DIR}/tests/opcua_types_fixture.bsd" --fixture-table
      DEPENDS cpkt::open62541_static tools/opcua/generate.py tools/opcua/c89_emitter.py
        tools/opcua/plugin_emitter.py tools/opcua/history_emitter.py tools/opcua/server_emitter.py tools/opcua/node_emitter.py tools/opcua/producer_emitter.py tools/opcua/creation_emitter.py tools/opcua/client_emitter.py tools/opcua/async_client_emitter.py tools/opcua/core_client_emitter.py tools/opcua/value_emitter.py tools/opcua/certificate_emitter.py tools/opcua/utility_emitter.py tools/opcua/format_emitter.py tools/opcua/security_emitter.py tools/opcua/policy_emitter.py tools/opcua/pubsub_emitter.py tools/opcua/codec_emitter.py tools/opcua/event_emitter.py tools/opcua/dynamic_emitter.py tools/opcua/eventloop_emitter.py tools/opcua/config_emitter.py tools/opcua/config_plugin_emitter.py tools/opcua/config_server_plugin_emitter.py tools/opcua/nodestore_emitter.py tests/opcua_types_fixture.bsd VERBATIM)
  cpkt_group_add_executable(cpkt_opcua_types_fixture_test tests/opcua_types_fixture_test.c
      src/opcua_types.c "${_cpkt_fixture_dir}/native/open62541/types_generated.c")
  cpkt_group_use_local_runtime(cpkt_opcua_types_fixture_test)
  cpkt_add_repo_warning_errors(cpkt_opcua_types_fixture_test)
  cpkt_group_target_command(target_include_directories cpkt_opcua_types_fixture_test BEFORE PRIVATE
      "${_cpkt_fixture_dir}" "${_cpkt_fixture_dir}/native")
  cpkt_group_target_command(target_compile_options cpkt_opcua_types_fixture_test PRIVATE -UNDEBUG -Dinline=)
  set_source_files_properties(tests/opcua_types_fixture_test.c src/opcua_types.c PROPERTIES COMPILE_OPTIONS "-std=c89;-pedantic-errors")
  cpkt_group_target_command(target_link_libraries cpkt_opcua_types_fixture_test PRIVATE cpkt_opcua_static)
  cpkt_group_add_executable(cpkt_opcua_types_cpp_test tests/opcua_types_cpp_test.cpp)
  cpkt_group_use_local_runtime(cpkt_opcua_types_cpp_test)
  cpkt_add_repo_warning_errors(cpkt_opcua_types_cpp_test)
  cpkt_group_set_target_properties(cpkt_opcua_types_cpp_test PROPERTIES CXX_STANDARD 98 CXX_STANDARD_REQUIRED YES CXX_EXTENSIONS NO)
  cpkt_group_target_command(target_link_libraries cpkt_opcua_types_cpp_test PRIVATE cpkt_opcua_static)
  if(CPKT_CAN_RUN_TARGET_EXECUTABLES)
    cpkt_group_add_test(NAME opcua_types_schema_fixture COMMAND cpkt_opcua_types_fixture_test)
    cpkt_group_add_test(NAME opcua_types_cpp COMMAND cpkt_opcua_types_cpp_test)
    cpkt_group_set_tests_properties(opcua_types_schema_fixture PROPERTIES LABELS "facade;opcua;memcheck" TIMEOUT 30)
  endif()
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    cpkt_group_add_executable(cpkt_opcua_types_alloc_test tests/opcua_types_test.c
          tests/opcua_types_native_peer.c tests/opcua_types_alloc_failure.c tests/opcua_callbacks_test.c tests/opcua_plugins_test.c tests/opcua_history_backend_test.c tests/opcua_memory_backend_test.c tests/opcua_certificate_test.c tests/opcua_certificate_native_peer.c tests/opcua_config_test.c tests/opcua_config_native_peer.c tests/opcua_format_test.c tests/opcua_transport_test.c tests/opcua_operations_test.c tests/opcua_nodestore_test.c tests/opcua_server_types_test.c tests/opcua_util_test.c tests/opcua_identifiers_test.c tests/opcua_nodes_test.c tests/opcua_producers_test.c tests/opcua_creation_test.c tests/opcua_external_test.c tests/opcua_client_test.c tests/opcua_async_client_test.c tests/opcua_core_client_test.c)
    cpkt_group_use_local_runtime(cpkt_opcua_types_alloc_test)
    cpkt_add_repo_warning_errors(cpkt_opcua_types_alloc_test)
    cpkt_group_target_command(target_compile_definitions cpkt_opcua_types_alloc_test PRIVATE CPKT_OPCUA_TYPES_ALLOC_FAILURE)
    cpkt_group_target_command(target_compile_options cpkt_opcua_types_alloc_test PRIVATE -UNDEBUG)
    cpkt_group_target_command(target_link_options cpkt_opcua_types_alloc_test PRIVATE -Wl,--wrap=calloc,--wrap=malloc,--wrap=realloc
          -Wl,--wrap=UA_Client_readValueAttribute,--wrap=UA_Client_call,--wrap=UA_Client_addVariableNode,--wrap=UA_Client_HistoryRead_raw,--wrap=UA_Client_readValueAttribute_async,--wrap=UA_Client_MonitoredItems_createEvent,--wrap=UA_Client_getSessionAuthenticationToken,--wrap=UA_Client_getEndpoints,--wrap=UA_Client_getNamespaceUri,--wrap=UA_HistoryDatabase_default)
    cpkt_group_target_command(target_link_libraries cpkt_opcua_types_alloc_test PRIVATE cpkt_opcua_static Threads::Threads)
    if(CPKT_CAN_RUN_TARGET_EXECUTABLES)
      cpkt_group_add_test(NAME opcua_types_allocation_failure COMMAND cpkt_opcua_types_alloc_test)
      cpkt_group_set_tests_properties(opcua_types_allocation_failure PROPERTIES LABELS "facade;integration;offline;opcua;memcheck" TIMEOUT 120)
    endif()
  endif()
  cpkt_group_add_test(NAME opcua_types_exports_portability
      COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/opcua_types_exports_portability_test.py"
        "${CMAKE_SOURCE_DIR}" "${CMAKE_BINARY_DIR}" "${CMAKE_C_COMPILER}")
  cpkt_group_set_tests_properties(opcua_types_exports_portability PROPERTIES LABELS "packaging;opcua" TIMEOUT 30)
  foreach(_cpkt_types_linkage IN ITEMS static shared)
    cpkt_group_add_executable(cpkt_opcua_types_${_cpkt_types_linkage}_test
          tests/opcua_types_test.c tests/opcua_types_native_peer.c tests/opcua_callbacks_test.c tests/opcua_plugins_test.c tests/opcua_history_backend_test.c tests/opcua_memory_backend_test.c tests/opcua_certificate_test.c tests/opcua_certificate_native_peer.c tests/opcua_config_test.c tests/opcua_config_native_peer.c tests/opcua_format_test.c tests/opcua_transport_test.c tests/opcua_operations_test.c tests/opcua_nodestore_test.c tests/opcua_server_types_test.c tests/opcua_util_test.c tests/opcua_identifiers_test.c tests/opcua_nodes_test.c tests/opcua_producers_test.c tests/opcua_creation_test.c tests/opcua_external_test.c tests/opcua_client_test.c tests/opcua_async_client_test.c tests/opcua_core_client_test.c)
    cpkt_group_use_local_runtime(cpkt_opcua_types_${_cpkt_types_linkage}_test
          cpkt::open62541_shared cpkt::openssl_ssl_shared cpkt::openssl_crypto_shared)
    cpkt_add_repo_warning_errors(cpkt_opcua_types_${_cpkt_types_linkage}_test)
    cpkt_group_target_command(target_compile_options cpkt_opcua_types_${_cpkt_types_linkage}_test PRIVATE -UNDEBUG)
    set_source_files_properties(tests/opcua_types_test.c PROPERTIES COMPILE_OPTIONS "-std=c89;-pedantic-errors")
    set_source_files_properties(tests/opcua_callbacks_test.c PROPERTIES COMPILE_OPTIONS "-std=c89;-pedantic-errors")
    set_source_files_properties(tests/opcua_history_backend_test.c tests/opcua_certificate_test.c tests/opcua_config_test.c tests/opcua_format_test.c tests/opcua_transport_test.c tests/opcua_operations_test.c tests/opcua_nodestore_test.c PROPERTIES COMPILE_OPTIONS "-std=c89;-pedantic-errors")
    set_source_files_properties(tests/opcua_plugins_test.c PROPERTIES COMPILE_OPTIONS "-std=c89;-pedantic-errors")
    set_source_files_properties(tests/opcua_util_test.c tests/opcua_identifiers_test.c tests/opcua_nodes_test.c tests/opcua_producers_test.c tests/opcua_creation_test.c tests/opcua_external_test.c tests/opcua_client_test.c tests/opcua_async_client_test.c tests/opcua_core_client_test.c PROPERTIES COMPILE_OPTIONS "-std=c89;-pedantic-errors")
    set_source_files_properties(tests/opcua_server_types_test.c PROPERTIES COMPILE_OPTIONS "-std=c89;-pedantic-errors")
    set_source_files_properties(tests/opcua_types_native_peer.c tests/opcua_memory_backend_test.c tests/opcua_certificate_native_peer.c tests/opcua_config_native_peer.c PROPERTIES COMPILE_OPTIONS "-std=c99")
    cpkt_group_target_command(target_link_libraries cpkt_opcua_types_${_cpkt_types_linkage}_test PRIVATE
          cpkt_opcua_${_cpkt_types_linkage} Threads::Threads)
    cpkt_group_add_test(NAME opcua_types_exports_${_cpkt_types_linkage}
          COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/opcua_types_exports_test.py"
            "${CMAKE_NM}" "${CMAKE_READELF}" "${CMAKE_SYSTEM_NAME}" "${CMAKE_C_COMPILER}" "$<TARGET_FILE:cpkt_opcua_${_cpkt_types_linkage}>"
            "${CMAKE_SOURCE_DIR}/src/opcua_facade_internal.h"
            "${CMAKE_SOURCE_DIR}/include/cpkt/opcua.h"
            "${CMAKE_SOURCE_DIR}/include/cpkt/opcua_types_base.h"
            "${CMAKE_SOURCE_DIR}/include/cpkt/opcua_util.h"
            "${CMAKE_SOURCE_DIR}/include/cpkt/opcua_callbacks.h"
            "${CPKT_OPCUA_GENERATED_DIR}/cpkt/opcua_plugins.h"
            "${CPKT_OPCUA_GENERATED_DIR}/cpkt/opcua_types.h")
    cpkt_group_set_tests_properties(opcua_types_exports_${_cpkt_types_linkage} PROPERTIES LABELS "packaging;opcua")
    if(CPKT_CAN_RUN_TARGET_EXECUTABLES)
      cpkt_group_add_test(NAME opcua_types_${_cpkt_types_linkage}
              COMMAND cpkt_opcua_types_${_cpkt_types_linkage}_test)
      cpkt_group_set_tests_properties(opcua_types_${_cpkt_types_linkage} PROPERTIES LABELS "facade;integration;offline;opcua;memcheck" TIMEOUT 120)
    endif()
  endforeach()
  if(CPKT_CAN_RUN_TARGET_EXECUTABLES)
    set(_cpkt_curl_harness_runner)
    foreach(_cpkt_runner_argument IN LISTS CPKT_TEST_EXECUTABLE_PREFIX)
      list(APPEND _cpkt_curl_harness_runner "--runner=${_cpkt_runner_argument}")
    endforeach()
    cpkt_group_add_test(
          NAME patch_series_portability
          COMMAND "${CMAKE_COMMAND}"
            "-DCPKT_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
            "-DCPKT_PATCH_TEST_ROOT=${CMAKE_BINARY_DIR}"
            -P "${CMAKE_SOURCE_DIR}/tests/patch_series_portability_test.cmake")
    cpkt_group_set_tests_properties(patch_series_portability PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
    cpkt_group_add_test(NAME opcua_c89_example COMMAND cpkt_opcua_c89_example)
    cpkt_group_add_test(NAME audio_sus_c89_example COMMAND cpkt_audio_sus_c89_example)
    cpkt_group_add_test(NAME audio_vox_intro_c89_example
          COMMAND cpkt_audio_vox_intro_c89_example)
    cpkt_group_add_test(NAME audio_live_vox_c89_example
          COMMAND cpkt_audio_live_vox_c89_example --smoke)
    cpkt_group_add_test(NAME sus_vox_intro_c89_example
          COMMAND cpkt_sus_vox_intro_c89_example)
    cpkt_group_add_test(NAME sus_live_vox_c89_example
          COMMAND cpkt_sus_live_vox_c89_example --smoke)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CPKT_TARGET_LIBC STREQUAL "musl")
      cpkt_group_add_test(NAME audio_live_vox_static_c89_example
              COMMAND cpkt_audio_live_vox_static_c89_example --smoke)
      cpkt_group_add_test(NAME sus_live_vox_static_c89_example
              COMMAND cpkt_sus_live_vox_static_c89_example --smoke)
      cpkt_group_add_test(
              NAME audio_sus_static_live_examples_are_static
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/static_executable_policy_test.sh"
                "$<TARGET_FILE:cpkt_audio_live_vox_static_c89_example>"
                "$<TARGET_FILE:cpkt_sus_live_vox_static_c89_example>")
      if(NOT CPKT_NATIVE_BOOTLIN_RUNTIME)
        cpkt_group_set_tests_properties(sus_live_vox_static_c89_example PROPERTIES ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:cpkt_sus_shared>:${CPKT_EXTERNAL_ROOT}/whisper/install/lib:${CPKT_EXTERNAL_ROOT}/curl/install/lib:${CPKT_EXTERNAL_ROOT}/openssl/install/lib:${CPKT_EXTERNAL_ROOT}/nghttp2/install/lib:${CPKT_EXTERNAL_ROOT}/libssh2/install/lib:${CPKT_EXTERNAL_ROOT}/zlib/install/lib")
      endif()
    endif()
    cpkt_group_add_test(
          NAME sus_live_startup_status
          COMMAND
            "${CMAKE_SOURCE_DIR}/tests/sus_live_startup_status_test.sh"
            ${CPKT_TEST_EXECUTABLE_PREFIX}
            "$<TARGET_FILE:cpkt_sus_live_vox_c89_example>")
    if(NOT CPKT_NATIVE_BOOTLIN_RUNTIME)
      cpkt_group_set_tests_properties(audio_live_vox_c89_example PROPERTIES ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:cpkt_audio_shared>:${CPKT_EXTERNAL_ROOT}/curl/install/lib:${CPKT_EXTERNAL_ROOT}/openssl/install/lib:${CPKT_EXTERNAL_ROOT}/nghttp2/install/lib:${CPKT_EXTERNAL_ROOT}/libssh2/install/lib:${CPKT_EXTERNAL_ROOT}/zlib/install/lib")
      cpkt_group_set_tests_properties(audio_sus_c89_example PROPERTIES ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:cpkt_sus_shared>:${CPKT_EXTERNAL_ROOT}/whisper/install/lib:${CPKT_EXTERNAL_ROOT}/curl/install/lib:${CPKT_EXTERNAL_ROOT}/openssl/install/lib:${CPKT_EXTERNAL_ROOT}/nghttp2/install/lib:${CPKT_EXTERNAL_ROOT}/libssh2/install/lib:${CPKT_EXTERNAL_ROOT}/zlib/install/lib")
      cpkt_group_set_tests_properties(sus_vox_intro_c89_example PROPERTIES ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:cpkt_sus_shared>:${CPKT_EXTERNAL_ROOT}/whisper/install/lib:${CPKT_EXTERNAL_ROOT}/curl/install/lib:${CPKT_EXTERNAL_ROOT}/openssl/install/lib:${CPKT_EXTERNAL_ROOT}/nghttp2/install/lib:${CPKT_EXTERNAL_ROOT}/libssh2/install/lib:${CPKT_EXTERNAL_ROOT}/zlib/install/lib")
      cpkt_group_set_tests_properties(sus_live_vox_c89_example PROPERTIES ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:cpkt_sus_shared>:${CPKT_EXTERNAL_ROOT}/whisper/install/lib:${CPKT_EXTERNAL_ROOT}/curl/install/lib:${CPKT_EXTERNAL_ROOT}/openssl/install/lib:${CPKT_EXTERNAL_ROOT}/nghttp2/install/lib:${CPKT_EXTERNAL_ROOT}/libssh2/install/lib:${CPKT_EXTERNAL_ROOT}/zlib/install/lib")
      cpkt_group_set_tests_properties(sus_live_startup_status PROPERTIES ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:cpkt_sus_shared>:${CPKT_EXTERNAL_ROOT}/whisper/install/lib:${CPKT_EXTERNAL_ROOT}/curl/install/lib:${CPKT_EXTERNAL_ROOT}/openssl/install/lib:${CPKT_EXTERNAL_ROOT}/nghttp2/install/lib:${CPKT_EXTERNAL_ROOT}/libssh2/install/lib:${CPKT_EXTERNAL_ROOT}/zlib/install/lib")
    endif()
    cpkt_group_add_test(
          NAME opcua_word_portability
          COMMAND
            "${CMAKE_SOURCE_DIR}/tests/opcua_word_portability_test.sh"
            "${CMAKE_SOURCE_DIR}"
            "${CPKT_EXTERNAL_ROOT}/open62541/install/include")
    cpkt_group_add_test(NAME abi_example_shared COMMAND cpkt_abi_smoke_shared)
    cpkt_group_add_test(NAME abi_example_static COMMAND cpkt_abi_smoke_static)
    cpkt_group_add_test(NAME whisper_example_shared COMMAND cpkt_whisper_smoke_shared)

    if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      cpkt_group_set_tests_properties(whisper_example_shared PROPERTIES ENVIRONMENT "DYLD_LIBRARY_PATH=${CPKT_EXTERNAL_ROOT}/whisper/install/lib")
      file(GLOB _cpkt_abi_runtime_dirs LIST_DIRECTORIES TRUE
                "${CPKT_EXTERNAL_ROOT}/*/install/lib")
      if(NOT _cpkt_abi_runtime_dirs)
        message(FATAL_ERROR "Darwin ABI smoke test has no bundled runtime libraries")
      endif()
      list(JOIN _cpkt_abi_runtime_dirs ":" _cpkt_abi_runtime_path)
      cpkt_group_set_tests_properties(abi_example_shared PROPERTIES ENVIRONMENT "DYLD_LIBRARY_PATH=${_cpkt_abi_runtime_path}")
    elseif(NOT CPKT_NATIVE_BOOTLIN_RUNTIME)
      cpkt_group_set_tests_properties(whisper_example_shared PROPERTIES ENVIRONMENT "LD_LIBRARY_PATH=${CPKT_EXTERNAL_ROOT}/whisper/install/lib")
    endif()
    if(NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      cpkt_group_add_test(NAME audio_facade_unit COMMAND cpkt_audio_facade_test)
      cpkt_group_add_test(
              NAME audio_process_capture_realtime
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/audio_process_capture_realtime_test.sh"
                ${CPKT_TEST_EXECUTABLE_PREFIX}
                "$<TARGET_FILE:cpkt_audio_process_capture_probe>")
      cpkt_group_add_test(
              NAME audio_process_playback_turns
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/audio_process_playback_turns_test.sh"
                ${CPKT_TEST_EXECUTABLE_PREFIX}
                "$<TARGET_FILE:cpkt_audio_process_playback_probe>")
      cpkt_group_add_test(
              NAME audio_runtime_loading_policy
              COMMAND
                bash "${CMAKE_SOURCE_DIR}/tests/audio_runtime_loading_policy_test.sh"
                "$<TARGET_FILE:cpkt_audio_static>"
                "$<TARGET_FILE:cpkt_audio_shared>"
                "${CMAKE_SOURCE_DIR}/src/audio.c"
                "${CMAKE_SOURCE_DIR}/CMakeLists.txt")
      cpkt_group_add_test(NAME sus_facade_unit COMMAND cpkt_sus_facade_test)
      if(NOT CPKT_NATIVE_BOOTLIN_RUNTIME)
        cpkt_group_set_tests_properties(sus_facade_unit PROPERTIES ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:cpkt_sus_shared>:${CPKT_EXTERNAL_ROOT}/whisper/install/lib:${CPKT_EXTERNAL_ROOT}/curl/install/lib:${CPKT_EXTERNAL_ROOT}/openssl/install/lib:${CPKT_EXTERNAL_ROOT}/nghttp2/install/lib:${CPKT_EXTERNAL_ROOT}/libssh2/install/lib:${CPKT_EXTERNAL_ROOT}/zlib/install/lib")
      endif()
      cpkt_group_add_test(
              NAME audio_sus_shared_abi
              COMMAND
                bash "${CMAKE_SOURCE_DIR}/tests/audio_sus_shared_abi_test.sh"
                "$<TARGET_FILE:cpkt_audio_shared>"
                "$<TARGET_FILE:cpkt_sus_shared>"
                "${CPKT_AUDIO_ABI_VERSION}"
                "${CPKT_SUS_ABI_VERSION}")
      cpkt_group_add_test(NAME sus_audio_integration COMMAND cpkt_sus_audio_integration_test)
      cpkt_group_set_tests_properties(sus_audio_integration PROPERTIES LABELS "integration;opt-in;sus")
      if(NOT CPKT_NATIVE_BOOTLIN_RUNTIME)
        cpkt_group_set_tests_properties(sus_audio_integration PROPERTIES ENVIRONMENT "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:cpkt_sus_shared>:${CPKT_EXTERNAL_ROOT}/whisper/install/lib:${CPKT_EXTERNAL_ROOT}/curl/install/lib:${CPKT_EXTERNAL_ROOT}/openssl/install/lib:${CPKT_EXTERNAL_ROOT}/nghttp2/install/lib:${CPKT_EXTERNAL_ROOT}/libssh2/install/lib:${CPKT_EXTERNAL_ROOT}/zlib/install/lib")
      endif()
      cpkt_group_add_test(NAME abi_test_shared COMMAND cpkt_abi_test_shared)
      cpkt_group_add_test(NAME abi_test_static COMMAND cpkt_abi_test_static)
      cpkt_group_add_test(NAME opcua_facade_integration COMMAND cpkt_opcua_facade_test)
      cpkt_group_add_test(
              NAME opcua_boundary_server_c99_client_c89
              COMMAND cpkt_opcua_facade_test server-is-c99-and-client-is-c89)
      cpkt_group_add_test(
              NAME opcua_boundary_server_c89_client_c99
              COMMAND cpkt_opcua_facade_test server-is-c89-and-client-is-c99)
      cpkt_group_add_test(
              NAME opcua_boundary_server_c89_client_c89
              COMMAND cpkt_opcua_facade_test server-is-c89-and-client-is-c89)
      cpkt_group_add_test(NAME opcua_facade_failure_modes COMMAND cpkt_opcua_facade_test failure-modes)
      string(REGEX MATCH "^[0-9]+" _cpkt_postgresql_oauth_major
              "${CPKT_POSTGRESQL_VERSION}")
      cpkt_group_get_target_property(_cpkt_postgresql_shared_location
              cpkt::postgresql_shared IMPORTED_LOCATION)
      get_filename_component(_cpkt_postgresql_library_dir
              "${_cpkt_postgresql_shared_location}" DIRECTORY)
      cpkt_group_add_test(NAME pdf_facade_static COMMAND cpkt_pdf_facade_static_test)
      cpkt_group_add_test(NAME pdf_facade_shared COMMAND cpkt_pdf_facade_shared_test)
      if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        cpkt_group_add_test(NAME pdf_api_surface COMMAND python3
                  "${CMAKE_SOURCE_DIR}/tests/pdf_api_surface_test.py"
                  "${CPKT_DEPENDENCY_BUILD_ROOT}/libharu/src/include/hpdf.h"
                  "${CMAKE_SOURCE_DIR}/include/cpkt/pdf.h"
                  "$<TARGET_FILE:cpkt_pdf_shared>"
                  "${CMAKE_NM}"
                  "${CMAKE_SOURCE_DIR}/cmake/exports/cpkt_pdf.txt")
      endif()
      file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/db-completion")
      cpkt_group_add_test(
              NAME clean_source_test_scratch
              COMMAND bash "${CMAKE_SOURCE_DIR}/tests/clean_source_test_scratch_test.sh"
                      "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(clean_source_test_scratch PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
      if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        set(_cpkt_auth_symbol_format macho)
      else()
        set(_cpkt_auth_symbol_format elf)
      endif()
      if(CPKT_TARGET_ID STREQUAL "x86_64-linux-gnu")
        cpkt_group_add_test(NAME contracts_out_of_source
                  COMMAND "${Python3_EXECUTABLE}"
                    "${CMAKE_SOURCE_DIR}/tests/contracts_out_of_source_test.py"
                    "${CMAKE_SOURCE_DIR}" "${CMAKE_BINARY_DIR}" "${CMAKE_C_COMPILER}")
        cpkt_group_set_tests_properties(contracts_out_of_source PROPERTIES LABELS "facade;packaging" TIMEOUT 240)
      endif()
      if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        set(_cpkt_db_symbol_format macho)
      else()
        set(_cpkt_db_symbol_format elf)
      endif()
      if(CPKT_TARGET_ID STREQUAL "x86_64-linux-gnu")
        foreach(_cpkt_catalog_generator IN ITEMS Ninja Makefiles)
          if(_cpkt_catalog_generator STREQUAL "Ninja")
            set(_cpkt_catalog_generator_name "Ninja")
          else()
            set(_cpkt_catalog_generator_name "Unix Makefiles")
          endif()
          cpkt_group_add_test(NAME export_catalog_dependency_${_cpkt_catalog_generator}
                      COMMAND "${Python3_EXECUTABLE}"
                        "${CMAKE_SOURCE_DIR}/tests/export_catalog_dependency_test.py"
                        --configured-binary-dir "${CMAKE_BINARY_DIR}"
                        --generator "${_cpkt_catalog_generator_name}")
          cpkt_group_set_tests_properties(export_catalog_dependency_${_cpkt_catalog_generator} PROPERTIES LABELS "facade;packaging" TIMEOUT 180)
        endforeach()
      endif()
      file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/sasl-empty-plugin-path")
      set(_cpkt_memcheck_facade_tests abi_test_shared abi_test_static audio_facade_unit sus_facade_unit opcua_facade_integration opcua_boundary_server_c99_client_c89 opcua_boundary_server_c89_client_c99 opcua_boundary_server_c89_client_c89 opcua_facade_failure_modes pdf_facade_static pdf_facade_shared)
      if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        list(APPEND _cpkt_memcheck_facade_tests
                  )
      endif()
      cpkt_group_set_tests_properties(opcua_facade_integration opcua_boundary_server_c99_client_c89 opcua_boundary_server_c89_client_c99 opcua_boundary_server_c89_client_c89 opcua_facade_failure_modes opcua_word_portability PROPERTIES LABELS "integration;offline;opcua" TIMEOUT 30)
      foreach(_cpkt_memcheck_test IN LISTS _cpkt_memcheck_facade_tests)
        cpkt_group_set_property(TEST ${_cpkt_memcheck_test} APPEND PROPERTY LABELS
                  facade memcheck)
      endforeach()
      cpkt_group_set_tests_properties(opcua_facade_integration PROPERTIES TIMEOUT 120)
      cpkt_group_set_tests_properties(opcua_facade_failure_modes PROPERTIES TIMEOUT 90)
      cpkt_group_add_test(
              NAME sus_model_catalog_metadata
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/sus_model_catalog_metadata_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME sus_cpu_backend_policy
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/sus_cpu_backend_policy_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME sus_segmented_policy
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/sus_segmented_policy_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME sus_log_policy
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/sus_log_policy_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME sus_network_boundary
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/sus_network_boundary_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME sus_static_runtime_policy
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/sus_static_runtime_policy_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME static_dependency_pic_policy
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/static_dependency_pic_policy_test.sh")
      cpkt_group_add_test(
              NAME linux_toolchain_sysroot_policy
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/linux_toolchain_sysroot_policy_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME osxcross_linker_cache_refresh
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/osxcross_linker_cache_refresh_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME repo_dependency_cache_policy
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/repo_dependency_cache_policy_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME repo_dependency_stale_root
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/repo_dependency_stale_root_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME external_project_toolchain_environment
              COMMAND
                "${CMAKE_COMMAND}"
                "-DCPKT_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
                "-DCPKT_TEST_BINARY_DIR=${CMAKE_BINARY_DIR}/external-project-toolchain-env-fixture"
                -P "${CMAKE_SOURCE_DIR}/tests/external_project_toolchain_env_test.cmake")
      cpkt_group_add_test(
              NAME pinned_toolchain_resolvers
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/toolchain_resolver_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME lifecycle_toolchain_resolvers
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/toolchain_resolver_test.sh"
                "${CMAKE_SOURCE_DIR}"
                "${CMAKE_SOURCE_DIR}/scripts/cpkt-toolchains.sh")
      cpkt_group_add_test(
              NAME aflpp_resolver_cleanup
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/aflpp_resolver_cleanup_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME dependency_archive_cache
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/dependency_archive_cache_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(NAME dependency_cache_network_hits
              COMMAND "${Python3_EXECUTABLE}"
                "${CMAKE_SOURCE_DIR}/tests/dependency_cache_network_hits_test.py"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(dependency_cache_network_hits PROPERTIES LABELS "packaging;smoke" TIMEOUT 60)
      cpkt_group_add_test(
              NAME dependency_cache_disabled
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/dependency_cache_disabled_test.sh"
                "${CMAKE_SOURCE_DIR}"
                "${CMAKE_SOURCE_DIR}/build/dependency-cache-disabled-external"
                "${CMAKE_SOURCE_DIR}/build/dependency-cache-disabled-build")
      cpkt_group_add_test(
              NAME darwin_install_name_normalization
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/darwin_install_name_normalization_test.sh"
                "${CMAKE_SOURCE_DIR}"
                "${CMAKE_COMMAND}")
      cpkt_group_set_tests_properties(darwin_install_name_normalization PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
      if(CPKT_TARGET_ID STREQUAL "x86_64-linux-gnu")
        cpkt_group_add_test(
                  NAME dependency_reuse_configure
                  COMMAND
                    "${CMAKE_SOURCE_DIR}/tests/dependency_reuse_configure_test.sh"
                    "${CMAKE_SOURCE_DIR}"
                    "${CMAKE_COMMAND}"
                    "${CMAKE_GENERATOR}"
                    "${CMAKE_MAKE_PROGRAM}"
                    "${CMAKE_TOOLCHAIN_FILE}"
                    "${CMAKE_BUILD_TYPE}")
        cpkt_group_set_tests_properties(dependency_reuse_configure PROPERTIES LABELS "packaging;smoke" TIMEOUT 60)
      endif()
      cpkt_group_add_test(
              NAME privacy_scan_failure
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/privacy_scan_failure_test.sh")
      cpkt_group_set_tests_properties(privacy_scan_failure PROPERTIES LABELS "packaging" TIMEOUT 30)
      cpkt_group_add_test(NAME source_archive_verify_failure
              COMMAND bash "${CMAKE_SOURCE_DIR}/tests/source_archive_verify_failure_test.sh")
      cpkt_group_set_tests_properties(source_archive_verify_failure PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
      foreach(_cpkt_install_generator IN ITEMS Ninja Makefiles)
        if(_cpkt_install_generator STREQUAL "Makefiles")
          set(_cpkt_install_generator_name "Unix Makefiles")
        else()
          set(_cpkt_install_generator_name "Ninja")
        endif()
        cpkt_group_add_test(NAME dependency_install_order_${_cpkt_install_generator}
                  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/dependency_install_order_test.py"
                    "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}" "${_cpkt_install_generator_name}")
        cpkt_group_set_tests_properties(dependency_install_order_${_cpkt_install_generator} PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
        cpkt_group_add_test(NAME open62541_openssl_provenance_${_cpkt_install_generator}
                  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/open62541_openssl_provenance_fixture_test.py"
                    "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}" "${_cpkt_install_generator_name}")
        cpkt_group_set_tests_properties(open62541_openssl_provenance_${_cpkt_install_generator} PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
      endforeach()
      cpkt_group_add_test(
              NAME dependency_component_targets
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/dependency_component_targets_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME package_assertions_elf_runpath
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/package_assertions_elf_runpath_test.sh")
      cpkt_group_set_tests_properties(package_assertions_elf_runpath PROPERTIES LABELS "packaging" TIMEOUT 30)
      cpkt_group_add_test(NAME opcua_format_optimized_compile
              COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/opcua_format_optimized_compile_test.py"
                "${CMAKE_CURRENT_BINARY_DIR}")
      cpkt_group_set_tests_properties(opcua_format_optimized_compile PROPERTIES LABELS "packaging;opcua" TIMEOUT 30)
      cpkt_group_add_test(NAME opcua_header_contract
              COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/opcua_header_contract_test.py" "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(opcua_header_contract PROPERTIES LABELS "packaging;opcua" TIMEOUT 30)
      cpkt_group_add_test(
              NAME package_assertions_cleanup
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/package_assertions_cleanup_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(package_assertions_cleanup PROPERTIES LABELS "packaging" TIMEOUT 30)
      cpkt_group_add_test(
              NAME package_failure_diagnostics
              COMMAND
                python3 "${CMAKE_SOURCE_DIR}/tests/package_failure_diagnostics_test.py"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(package_failure_diagnostics PROPERTIES LABELS "packaging" TIMEOUT 30)
      cpkt_group_add_test(
              NAME package_consumer_execution
              COMMAND python3 "${CMAKE_SOURCE_DIR}/tests/package_consumer_execution_test.py"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(package_consumer_execution PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
      cpkt_group_add_test(
              NAME package_archive_layout
              COMMAND python3 "${CMAKE_SOURCE_DIR}/tests/package_archive_layout_test.py"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(package_archive_layout PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
      cpkt_group_add_test(
              NAME package_verify_toolchain_tools
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/package_verify_toolchain_tools_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(package_verify_toolchain_tools PROPERTIES LABELS "packaging" TIMEOUT 30)
      cpkt_group_add_test(
              NAME native_hardening_host
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/native_hardening_host_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(native_hardening_host PROPERTIES LABELS "smoke" TIMEOUT 30)
      cpkt_group_add_test(
              NAME afl_crash_gate
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/run_afl_fuzz_crash_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(afl_crash_gate PROPERTIES LABELS "fuzz;smoke" TIMEOUT 30)
      cpkt_group_add_test(
              NAME fuzz_toolchain_policy
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/fuzz_toolchain_policy_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_set_tests_properties(fuzz_toolchain_policy PROPERTIES LABELS "fuzz;smoke" TIMEOUT 30)
      cpkt_group_add_test(NAME package_integration_contracts
              COMMAND "${CPKT_OPERATION_PYTHON}" "${CMAKE_SOURCE_DIR}/tests/package_integration_contract_test.py")
      cpkt_group_add_test(NAME github_actions_contracts
              COMMAND "${CPKT_OPERATION_PYTHON}" "${CMAKE_SOURCE_DIR}/tests/github_actions_contract_test.py")
      cpkt_group_add_test(
              NAME lifecycle_surface
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/lifecycle_surface_test.sh")
      cpkt_group_set_tests_properties(lifecycle_surface PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
      cpkt_group_add_test(
              NAME package_install_smoke_args
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/package_install_smoke_args_test.sh")
      cpkt_group_set_tests_properties(package_install_smoke_args PROPERTIES LABELS "packaging;smoke" TIMEOUT 30)
      cpkt_group_add_test(
              NAME receiver_style_examples
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/receiver_style_examples_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME facade_c89_target_policy
              COMMAND
                bash
                "${CMAKE_SOURCE_DIR}/tests/facade_c89_target_policy_test.sh"
                "${CMAKE_SOURCE_DIR}")
      if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
        set(_cpkt_openssl_catalog_symbol_format macho)
        set(_cpkt_openssl_catalog_symbol_tool "${CMAKE_NM}")
      else()
        set(_cpkt_openssl_catalog_symbol_format elf)
        set(_cpkt_openssl_catalog_symbol_tool "${CMAKE_READELF}")
      endif()
      if(CPKT_TARGET_ID STREQUAL "x86_64-linux-gnu")
        if(CPKT_OPENSSL_API_INVENTORY_CLANG AND
                    NOT EXISTS "${CPKT_OPENSSL_API_INVENTORY_CLANG}")
          unset(CPKT_OPENSSL_API_INVENTORY_CLANG CACHE)
        endif()
        find_program(CPKT_OPENSSL_API_INVENTORY_CLANG NAMES clang REQUIRED
                  NO_CMAKE_FIND_ROOT_PATH)
      endif()
      cpkt_group_add_test(
              NAME audio_sus_header_facade
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/audio_sus_header_facade_test.sh"
                "${CMAKE_SOURCE_DIR}")
      cpkt_group_add_test(
              NAME audio_sus_spec_consistency
              COMMAND
                "${CMAKE_SOURCE_DIR}/tests/audio_sus_spec_consistency_test.sh"
                "${CMAKE_SOURCE_DIR}")
      if(CPKT_TARGET_ID STREQUAL "x86_64-linux-gnu")
        cpkt_group_add_test(
                  NAME clangd_comment_gate
                  COMMAND
                    bash
                    "${CMAKE_SOURCE_DIR}/tests/clangd_comment_gate_test.sh"
                    "${CMAKE_SOURCE_DIR}/scripts/verify-clangd-surface.sh")
        cpkt_group_set_tests_properties(clangd_comment_gate PROPERTIES LABELS "smoke" TIMEOUT 30)
        cpkt_group_add_test(
                  NAME clangd_surface
                  COMMAND
                    "${CMAKE_SOURCE_DIR}/scripts/verify-clangd-surface.sh"
                    "${CMAKE_SOURCE_DIR}"
                    "${CMAKE_BINARY_DIR}")
      endif()
    endif()
  endif()
  if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(_cpkt_lua_inventory_symbol_format macho)
  else()
    set(_cpkt_lua_inventory_symbol_format elf)
  endif()
endif()
if(CPKT_ENABLE_FUZZING)
  cpkt_group_add_executable(cpkt_opcua_facade_fuzz fuzz/opcua_facade_fuzz.c)
  cpkt_group_use_local_runtime(cpkt_opcua_facade_fuzz)
  cpkt_configure_afl_target(cpkt_opcua_facade_fuzz)
  cpkt_group_target_command(target_include_directories cpkt_opcua_facade_fuzz PRIVATE "${CMAKE_SOURCE_DIR}/include")
  cpkt_group_target_command(target_link_libraries cpkt_opcua_facade_fuzz PRIVATE cpkt_opcua_static)
endif()
include(cmake/CpktPackage.cmake)
if(CPKT_BUILD_TESTS)
  cpkt_group_add_test(NAME repository_boundary
      COMMAND "${CPKT_OPERATION_PYTHON}" "${CMAKE_SOURCE_DIR}/tests/repository_boundary_test.py")
endif()

# Each linked shared module proves an owned static native/facade archive is PIC.
if(CPKT_BUILD_TESTS AND NOT CPKT_FACADE_ONLY)
  cpkt_group_add_library(cpkt_static_archive_pic_pdf_facade SHARED tests/sdk-consumers/cpkt_pdf_facade_strict.c)
  cpkt_group_target_command(target_compile_options cpkt_static_archive_pic_pdf_facade PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_static_archive_pic_pdf_facade)
  cpkt_group_target_command(target_link_libraries cpkt_static_archive_pic_pdf_facade PRIVATE cpkt_pdf_static)
  cpkt_group_add_library(cpkt_static_archive_pic_open62541 SHARED tests/sdk-consumers/cpkt_open62541.c)
  cpkt_group_target_command(target_compile_options cpkt_static_archive_pic_open62541 PRIVATE -std=c99)
  cpkt_add_repo_warning_errors(cpkt_static_archive_pic_open62541)
  cpkt_group_target_command(target_link_libraries cpkt_static_archive_pic_open62541 PRIVATE cpkt::open62541_static)
  cpkt_group_add_library(cpkt_static_archive_pic_audio_facade SHARED tests/sdk-consumers/cpkt_audio_facade_strict.c)
  cpkt_group_target_command(target_compile_options cpkt_static_archive_pic_audio_facade PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_static_archive_pic_audio_facade)
  cpkt_group_target_command(target_link_libraries cpkt_static_archive_pic_audio_facade PRIVATE cpkt_audio_static)
  cpkt_group_add_library(cpkt_static_archive_pic_opcua_facade SHARED tests/sdk-consumers/cpkt_opcua_facade_strict.c)
  cpkt_group_target_command(target_compile_options cpkt_static_archive_pic_opcua_facade PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_static_archive_pic_opcua_facade)
  cpkt_group_target_command(target_link_libraries cpkt_static_archive_pic_opcua_facade PRIVATE cpkt_opcua_static)
  cpkt_group_add_library(cpkt_static_archive_pic_sus_facade SHARED tests/sdk-consumers/cpkt_sus_facade_strict.c)
  cpkt_group_target_command(target_compile_options cpkt_static_archive_pic_sus_facade PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_static_archive_pic_sus_facade)
  cpkt_group_target_command(target_link_libraries cpkt_static_archive_pic_sus_facade PRIVATE cpkt_sus_static)
  cpkt_group_set_target_properties(cpkt_static_archive_pic_sus_facade PROPERTIES LINKER_LANGUAGE CXX)
  cpkt_group_add_library(cpkt_static_archive_pic_audio_sus_facade SHARED tests/sdk-consumers/cpkt_audio_sus_facade_strict.c)
  cpkt_group_target_command(target_compile_options cpkt_static_archive_pic_audio_sus_facade PRIVATE -std=c89)
  cpkt_add_repo_warning_errors(cpkt_static_archive_pic_audio_sus_facade)
  cpkt_group_target_command(target_link_libraries cpkt_static_archive_pic_audio_sus_facade PRIVATE cpkt_sus_static)
  cpkt_group_set_target_properties(cpkt_static_archive_pic_audio_sus_facade PROPERTIES LINKER_LANGUAGE CXX)
  if(CPKT_CAN_RUN_TARGET_EXECUTABLES)
    cpkt_group_add_test(NAME static_archive_pic_link
      COMMAND "${CMAKE_SOURCE_DIR}/tests/static_archive_pic_link_test.sh"
        "$<TARGET_FILE:cpkt_static_archive_pic_pdf_facade>"
        "$<TARGET_FILE:cpkt_static_archive_pic_open62541>"
        "$<TARGET_FILE:cpkt_static_archive_pic_audio_facade>"
        "$<TARGET_FILE:cpkt_static_archive_pic_opcua_facade>"
        "$<TARGET_FILE:cpkt_static_archive_pic_sus_facade>"
        "$<TARGET_FILE:cpkt_static_archive_pic_audio_sus_facade>"
    )
  endif()
endif()
