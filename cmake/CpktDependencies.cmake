include(ExternalProject)

include("${CMAKE_CURRENT_LIST_DIR}/CpktDependencyArchiveCache.cmake")
function(cpkt_external_install_byproducts out_var)
if(CMAKE_VERSION VERSION_LESS 3.26)
set(${out_var} ${ARGN} PARENT_SCOPE)
else()
set(${out_var} INSTALL_BYPRODUCTS ${ARGN} PARENT_SCOPE)
endif()
endfunction()
macro(cpkt_cached_external_project_add)
set(_cpkt_ep_args ${ARGV})
list(FIND _cpkt_ep_args "URL" _cpkt_ep_url_index)
list(FIND _cpkt_ep_args "URL_HASH" _cpkt_ep_hash_index)
if(_cpkt_ep_url_index LESS 1 OR _cpkt_ep_hash_index LESS 0 OR _cpkt_ep_hash_index LESS _cpkt_ep_url_index)
message(FATAL_ERROR "cpkt_cached_external_project_add requires URL and URL_HASH after the target name")
endif()
math(EXPR _cpkt_ep_url_start "${_cpkt_ep_url_index} + 1")
math(EXPR _cpkt_ep_url_count "${_cpkt_ep_hash_index} - ${_cpkt_ep_url_start}")
if(_cpkt_ep_url_count LESS 1)
message(FATAL_ERROR "cpkt_cached_external_project_add requires at least one URL")
endif()
list(SUBLIST _cpkt_ep_args ${_cpkt_ep_url_start} ${_cpkt_ep_url_count} _cpkt_ep_urls)
math(EXPR _cpkt_ep_hash_value_index "${_cpkt_ep_hash_index} + 1")
list(GET _cpkt_ep_args ${_cpkt_ep_hash_value_index} _cpkt_ep_hash)
string(REGEX REPLACE "^SHA256=" "" _cpkt_ep_sha256 "${_cpkt_ep_hash}")
string(LENGTH "${_cpkt_ep_sha256}" _cpkt_ep_sha256_length)
if(NOT _cpkt_ep_hash MATCHES "^SHA256="
      OR NOT _cpkt_ep_sha256_length EQUAL 64
      OR NOT "${_cpkt_ep_sha256}" MATCHES "^[A-Fa-f0-9]+$")
message(FATAL_ERROR "cpkt_cached_external_project_add requires URL_HASH SHA256=<digest>")
endif()
list(FIND _cpkt_ep_args "DOWNLOAD_NAME" _cpkt_ep_download_name_index)
if(_cpkt_ep_download_name_index LESS 0)
list(GET _cpkt_ep_urls 0 _cpkt_ep_name_url)
string(REGEX REPLACE "[?#].*$" "" _cpkt_ep_name_url "${_cpkt_ep_name_url}")
get_filename_component(_cpkt_ep_archive_name "${_cpkt_ep_name_url}" NAME)
else()
math(EXPR _cpkt_ep_download_name_value_index "${_cpkt_ep_download_name_index} + 1")
list(GET _cpkt_ep_args ${_cpkt_ep_download_name_value_index} _cpkt_ep_archive_name)
endif()
if(_cpkt_ep_archive_name STREQUAL "")
message(FATAL_ERROR "cpkt_cached_external_project_add could not determine an archive name")
endif()
cpkt_acquire_dependency_archive(_cpkt_ep_cached_archive
    NAME "${_cpkt_ep_archive_name}"
    SHA256 "${_cpkt_ep_sha256}"
    URLS ${_cpkt_ep_urls}
    SEED_PATHS "${CPKT_DOWNLOAD_ROOT}/${_cpkt_ep_archive_name}")
math(EXPR _cpkt_ep_remove_count "${_cpkt_ep_url_count} + 1")
foreach(_cpkt_ep_remove_index RANGE 1 ${_cpkt_ep_remove_count})
list(REMOVE_AT _cpkt_ep_args ${_cpkt_ep_url_index})
endforeach()
list(INSERT _cpkt_ep_args ${_cpkt_ep_url_index} URL "${_cpkt_ep_cached_archive}")
ExternalProject_Add(${_cpkt_ep_args})
endmacro()
function(cpkt_order_shared_install shared_project static_project)
ExternalProject_Add_StepTargets(${static_project} install)
ExternalProject_Add_StepTargets(${shared_project} build install)
ExternalProject_Add_StepDependencies(${shared_project} install
    ${static_project}-install)
endfunction()


function(cpkt_record_dependency_target target_name)
set_property(GLOBAL APPEND PROPERTY CPKT_DEPENDENCY_TARGETS "${target_name}")
endfunction()
function(cpkt_component_producer_prerequisites output component)
if(NOT DEFINED CPKT_INVENTORY)
set(${output} "${ARGN}" PARENT_SCOPE)
return()
endif()
string(JSON _count LENGTH "${CPKT_INVENTORY}" components "${component}" dependencies)
set(_targets "")
if(_count GREATER 0)
math(EXPR _last "${_count} - 1")
foreach(_index RANGE 0 ${_last})
string(JSON _dependency GET "${CPKT_INVENTORY}" components "${component}" dependencies ${_index})
get_property(_registered GLOBAL PROPERTY "CPKT_PRODUCER_TARGETS_${_dependency}" SET)
if(NOT _registered)
message(FATAL_ERROR "${component} prerequisite ${_dependency} has not been validated")
endif()
get_property(_owned GLOBAL PROPERTY "CPKT_PRODUCER_TARGETS_${_dependency}")
list(APPEND _targets ${_owned})
endforeach()
endif()
set(${output} "${_targets}" PARENT_SCOPE)
endfunction()
function(cpkt_require_dependency_file path label)
if(NOT EXISTS "${path}")
message(FATAL_ERROR
      "${label} was not found at ${path}\n"
      "Provide the dependency tree for this preset under CPKT_EXTERNAL_ROOT.\n"
      "Run make deps-all PRESET=<preset> to prepare the owning dependency graph.")
endif()
endfunction()
function(cpkt_get_external_c_flags out_var)
set(_flags "-O2 -DNDEBUG -g0")
if(CMAKE_C_COMPILER_ID MATCHES "^(AppleClang|Clang|GNU)$")
string(APPEND _flags
      " -fmacro-prefix-map=${CPKT_DEPENDENCY_BUILD_ROOT}=deps-build"
      " -fmacro-prefix-map=${CPKT_EXTERNAL_ROOT}=deps"
    )
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
string(APPEND _flags " -include stdint.h -include sys/types.h")
if(CPKT_MACOS_DEPLOYMENT_TARGET)
string(APPEND _flags
        " -mmacosx-version-min=${CPKT_MACOS_DEPLOYMENT_TARGET}")
endif()
endif()
if(NOT "${CMAKE_C_FLAGS}" STREQUAL "")
set(_flags "${CMAKE_C_FLAGS} ${_flags}")
endif()
string(STRIP "${_flags}" _flags)
set(${out_var} "${_flags}" PARENT_SCOPE)
endfunction()
function(cpkt_get_external_cxx_flags out_var)
set(_flags "-O2 -DNDEBUG -g0")
if(CMAKE_CXX_COMPILER_ID MATCHES "^(AppleClang|Clang|GNU)$")
string(APPEND _flags
      " -fmacro-prefix-map=${CPKT_DEPENDENCY_BUILD_ROOT}=deps-build"
      " -fmacro-prefix-map=${CPKT_EXTERNAL_ROOT}=deps"
    )
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
string(APPEND _flags " -include stdint.h -include sys/types.h")
if(CPKT_MACOS_DEPLOYMENT_TARGET)
string(APPEND _flags
        " -mmacosx-version-min=${CPKT_MACOS_DEPLOYMENT_TARGET}")
endif()
endif()
if(NOT "${CMAKE_CXX_FLAGS}" STREQUAL "")
set(_flags "${CMAKE_CXX_FLAGS} ${_flags}")
endif()
string(STRIP "${_flags}" _flags)
set(${out_var} "${_flags}" PARENT_SCOPE)
endfunction()
function(cpkt_append_external_pkg_config_env_args out_var)
set(_args ${${out_var}})
set(_pkg_config_dirs "")
foreach(_prefix_var IN ITEMS CPKT_CORE_PREFIX CPKT_LIBPNG_PREFIX)
if(DEFINED ${_prefix_var} AND NOT "${${_prefix_var}}" STREQUAL "")
list(APPEND _pkg_config_dirs
        "${${_prefix_var}}/lib/pkgconfig"
        "${${_prefix_var}}/share/pkgconfig")
endif()
endforeach()
if(_pkg_config_dirs)
list(REMOVE_DUPLICATES _pkg_config_dirs)
string(JOIN ":" _pkg_config_libdir ${_pkg_config_dirs})
else()
set(_pkg_config_libdir "${CPKT_EXTERNAL_ROOT}/.pkgconfig-empty")
endif()
list(APPEND _args
    PKG_CONFIG_PATH=
    PKG_CONFIG_DIR=
    PKG_CONFIG_LIBDIR=${_pkg_config_libdir})
set(${out_var} "${_args}" PARENT_SCOPE)
endfunction()
function(cpkt_append_darwin_external_env_args out_var)
set(_args ${${out_var}})
cpkt_append_external_pkg_config_env_args(_args)
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
foreach(_cpkt_required_var IN ITEMS
        CMAKE_C_COMPILER
        CMAKE_CXX_COMPILER
        CMAKE_AR
        CMAKE_RANLIB
        CMAKE_STRIP
        CMAKE_NM)
if(NOT DEFINED ${_cpkt_required_var}
          OR "${${_cpkt_required_var}}" STREQUAL "")
message(FATAL_ERROR
          "Darwin external builds require ${_cpkt_required_var}")
endif()
endforeach()
list(APPEND _args
      CC=${CMAKE_C_COMPILER}
      CXX=${CMAKE_CXX_COMPILER}
      AR=${CMAKE_AR}
      RANLIB=${CMAKE_RANLIB}
      STRIP=${CMAKE_STRIP}
      NM=${CMAKE_NM}
    )
if(CMAKE_OSX_SYSROOT)
list(APPEND _args "SDKROOT=${CMAKE_OSX_SYSROOT}")
endif()
if(CPKT_MACOS_DEPLOYMENT_TARGET)
list(APPEND _args
        MACOSX_DEPLOYMENT_TARGET=${CPKT_MACOS_DEPLOYMENT_TARGET})
endif()
if(CPKT_OSXCROSS_ROOT)
list(APPEND _args
        PATH=${CPKT_OSXCROSS_BIN_DIR}:$ENV{PATH}
        LD_LIBRARY_PATH=${CPKT_OSXCROSS_ROOT}/lib:$ENV{LD_LIBRARY_PATH})
endif()
if(CPKT_OSXCROSS_ROOT AND CMAKE_LINKER)
list(APPEND _args LDFLAGS=--ld-path=${CMAKE_LINKER})
endif()
endif()
set(${out_var} "${_args}" PARENT_SCOPE)
endfunction()
function(cpkt_append_pinned_external_toolchain_env_args out_var)
set(_args ${${out_var}})
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CPKT_BUILD_DEPENDENCIES)
foreach(_cpkt_required_var IN ITEMS
        CPKT_TOOLCHAIN_ROOT
        CMAKE_C_COMPILER
        CMAKE_CXX_COMPILER
        CMAKE_LINKER
        CMAKE_AR
        CMAKE_RANLIB
        CMAKE_STRIP
        CMAKE_NM
        CMAKE_OBJCOPY
        CMAKE_OBJDUMP
        CMAKE_ADDR2LINE
        CMAKE_READELF)
if(NOT DEFINED ${_cpkt_required_var}
          OR "${${_cpkt_required_var}}" STREQUAL "")
message(FATAL_ERROR
          "Pinned Linux external builds require ${_cpkt_required_var}")
endif()
endforeach()
set(_cpkt_toolchain_bin "${CPKT_TOOLCHAIN_ROOT}/bin")
if(NOT IS_DIRECTORY "${_cpkt_toolchain_bin}")
message(FATAL_ERROR
        "Pinned Linux toolchain bin directory is missing: ${_cpkt_toolchain_bin}")
endif()
list(APPEND _args
      PATH=${_cpkt_toolchain_bin}:$ENV{PATH}
      CC=${CMAKE_C_COMPILER}
      CXX=${CMAKE_CXX_COMPILER}
      LD=${CMAKE_LINKER}
      AR=${CMAKE_AR}
      RANLIB=${CMAKE_RANLIB}
      STRIP=${CMAKE_STRIP}
      NM=${CMAKE_NM}
      OBJCOPY=${CMAKE_OBJCOPY}
      OBJDUMP=${CMAKE_OBJDUMP}
      ADDR2LINE=${CMAKE_ADDR2LINE}
      READELF=${CMAKE_READELF})
endif()
cpkt_append_darwin_external_env_args(_args)
set(${out_var} "${_args}" PARENT_SCOPE)
endfunction()
function(cpkt_get_external_cmake_step_commands build_out_var install_out_var)
set(_build_command ${CMAKE_COMMAND} --build . --parallel ${CPKT_DEPENDENCY_BUILD_JOBS})
set(_install_command ${CMAKE_COMMAND} --install .)
set(_env_args "")
cpkt_append_pinned_external_toolchain_env_args(_env_args)
if(_env_args)
set(_build_command ${CMAKE_COMMAND} -E env ${_env_args} ${_build_command})
set(_install_command ${CMAKE_COMMAND} -E env ${_env_args} ${_install_command})
endif()
set(${build_out_var} "${_build_command}" PARENT_SCOPE)
set(${install_out_var} "${_install_command}" PARENT_SCOPE)
endfunction()
function(cpkt_get_external_cmake_configure_command out_var)
set(_configure_command ${CMAKE_COMMAND} -S <SOURCE_DIR> -B <BINARY_DIR>)
if(CMAKE_GENERATOR)
list(APPEND _configure_command -G "${CMAKE_GENERATOR}")
endif()
set(_env_args "")
cpkt_append_pinned_external_toolchain_env_args(_env_args)
if(_env_args)
set(_configure_command ${CMAKE_COMMAND} -E env ${_env_args} ${_configure_command})
endif()
set(${out_var} "${_configure_command}" PARENT_SCOPE)
endfunction()
function(cpkt_get_strip_dependency_install_command out_var install_dir)
if(NOT CMAKE_STRIP)
message(FATAL_ERROR "CMAKE_STRIP is required when building release dependencies")
endif()
set(_strip_static_archives ON)
set(_strip_shared_libraries ON)
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
set(_strip_static_archives OFF)
set(_strip_shared_libraries OFF)
endif()
set(_command
    ${CMAKE_COMMAND}
      -DCPKT_STRIP_BIN=${CMAKE_STRIP}
      -DCPKT_STRIP_ROOT=${install_dir}
      -DCPKT_STRIP_STATIC_ARCHIVES=${_strip_static_archives}
      -DCPKT_STRIP_SHARED_LIBRARIES=${_strip_shared_libraries}
      -P ${CMAKE_SOURCE_DIR}/cmake/strip_dependency_install_tree.cmake
  )
set(${out_var} "${_command}" PARENT_SCOPE)
endfunction()
function(cpkt_append_common_external_cmake_args out_var)
set(_args
    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
    -DCMAKE_LINKER=${CMAKE_LINKER}
    -DCMAKE_AR=${CMAKE_AR}
    -DCMAKE_RANLIB=${CMAKE_RANLIB}
    -DCMAKE_STRIP=${CMAKE_STRIP}
    -DCMAKE_NM=${CMAKE_NM}
    -DCMAKE_OBJCOPY=${CMAKE_OBJCOPY}
    -DCMAKE_OBJDUMP=${CMAKE_OBJDUMP}
    -DCMAKE_ADDR2LINE=${CMAKE_ADDR2LINE}
    -DCMAKE_READELF=${CMAKE_READELF}
    -Wno-dev
  )
if(CMAKE_TOOLCHAIN_FILE)
list(APPEND _args -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE})
endif()
if(CMAKE_CROSSCOMPILING)
list(APPEND _args -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
list(APPEND _args
      "-DCMAKE_OSX_SYSROOT:PATH=${CMAKE_OSX_SYSROOT}"
      -DCMAKE_OSX_DEPLOYMENT_TARGET=${CPKT_MACOS_DEPLOYMENT_TARGET}
      -DCMAKE_INSTALL_NAME_DIR=@rpath
      -DCMAKE_BUILD_WITH_INSTALL_NAME_DIR=ON
      -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON)
if(CMAKE_CROSSCOMPILING)
list(APPEND _args
      -DCPKT_OSXCROSS_HOST=${CPKT_OSXCROSS_HOST}
      -DCPKT_MACOS_DEPLOYMENT_TARGET=${CPKT_MACOS_DEPLOYMENT_TARGET})
endif()
endif()
cpkt_get_external_c_flags(_cpkt_external_c_flags)
list(APPEND _args -DCMAKE_C_FLAGS=${_cpkt_external_c_flags})
set(${out_var} "${_args}" PARENT_SCOPE)
endfunction()
function(cpkt_append_common_external_cxx_cmake_args out_var)
cpkt_append_common_external_cmake_args(_args)
list(APPEND _args
    -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
  )
cpkt_get_external_cxx_flags(_cpkt_external_cxx_flags)
list(APPEND _args -DCMAKE_CXX_FLAGS=${_cpkt_external_cxx_flags})
set(${out_var} "${_args}" PARENT_SCOPE)
endfunction()
include("${CMAKE_CURRENT_LIST_DIR}/dependencies/libpng.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/dependencies/libharu.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/dependencies/miniaudio.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/dependencies/whisper.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/dependencies/open62541.cmake")
function(cpkt_configure_dependencies)
  include("${CMAKE_SOURCE_DIR}/cmake/CpktCoreImports.cmake")
  cpkt_import_core()
cpkt_prepare_dependency_component(
    NAME libpng
    BUILD_ROOT "${CPKT_DEPENDENCY_BUILD_ROOT}/libpng"
    INSTALL_ROOT "${CPKT_EXTERNAL_ROOT}/libpng/install"
    VARIABLES CPKT_LIBPNG_VERSION
    DEPENDS zlib
    INPUT_FILES
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/CpktDependencies.cmake"
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/dependencies/libpng.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyContract.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyArchiveCache.cmake")
cpkt_prepare_dependency_component(
    NAME libharu
    BUILD_ROOT "${CPKT_DEPENDENCY_BUILD_ROOT}/libharu"
    INSTALL_ROOT "${CPKT_EXTERNAL_ROOT}/libharu/install"
    VARIABLES CPKT_LIBHARU_VERSION
    DEPENDS libpng zlib
    INPUT_FILES
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/CpktDependencies.cmake"
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/dependencies/libharu.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyContract.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyArchiveCache.cmake")
cpkt_prepare_dependency_component(
    NAME miniaudio
    BUILD_ROOT "${CPKT_DEPENDENCY_BUILD_ROOT}/miniaudio"
    INSTALL_ROOT "${CPKT_EXTERNAL_ROOT}/miniaudio/install"
    VARIABLES CPKT_MINIAUDIO_VERSION
    INPUT_FILES
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/CpktDependencies.cmake"
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/dependencies/miniaudio.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyContract.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyArchiveCache.cmake")
cpkt_prepare_dependency_component(
    NAME whisper
    BUILD_ROOT "${CPKT_DEPENDENCY_BUILD_ROOT}/whisper"
    INSTALL_ROOT "${CPKT_EXTERNAL_ROOT}/whisper/install"
    VARIABLES CPKT_WHISPER_VERSION CPKT_SUS_CPU_ONLY
    INPUT_FILES
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/CpktDependencies.cmake"
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/dependencies/whisper.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyContract.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyArchiveCache.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/patch_whisper_buildinfo.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/patches/whisper.series"
      "${CMAKE_SOURCE_DIR}/cmake/patches/whisper_ggml_validation_logging.patch")
cpkt_prepare_dependency_component(
    NAME open62541
    BUILD_ROOT "${CPKT_DEPENDENCY_BUILD_ROOT}/open62541"
    INSTALL_ROOT "${CPKT_EXTERNAL_ROOT}/open62541/install"
    VARIABLES CPKT_OPEN62541_VERSION CPKT_OPEN62541_PATCHSET
    DEPENDS openssl mqttc
    INPUT_FILES
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/CpktDependencies.cmake"
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/dependencies/open62541.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyContract.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyArchiveCache.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/apply_patch_series.cmake"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/series"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0001-prefix-embedded-mqtt-c-symbols.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0003-stub-posix-ethernet-when-packet-headers-are-missing.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0004-link-bundled-openssl-crypto.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0005-route-key-derivation-errors-through-logger.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0006-check-default-history-allocations.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0007-safe-reentrant-async-result-callbacks.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0008-preserve-date-parser-overflow-guard-direction.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0009-release-method-argument-ownership.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0010-use-external-source-notification-slots.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0011-check-memory-history-backend-allocations.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0012-check-certificate-trust-allocations.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0013-own-filestore-policy-metadata.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0014-own-datatype-copy-metadata.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0015-use-mutable-ec-keygen-argument.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0016-fix-variant-range-moves.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0017-preserve-event-source-free-failures.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0018-copy-client-config-owned-values.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0019-check-node-copy-and-filestore-helpers.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0020-check-discovery-and-reverse-connect.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0021-install-native-formatter-and-fix-minima.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0022-check-default-access-control-allocations.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0023-pin-reverse-connect-iteration-handles.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0024-define-discovery-callback-and-unavailable-policies.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0025-preserve-accept-all-certificate-logger.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0026-count-json-string-closing-quote.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0027-block-on-posix-stdout-lock.patch"
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0028-keep-disabled-lock-assert-warning-clean.patch")
set(_all_dependency_targets "")
foreach(_component IN LISTS CPKT_ACTIVE_COMPONENTS)
string(JSON _external ERROR_VARIABLE _owned GET "${CPKT_INVENTORY}" components "${_component}" external)
if(NOT _owned)
  continue()
endif()
string(JSON _owner GET "${CPKT_INVENTORY}" components "${_component}" group)
string(REPLACE "-" "_" _function "cpkt_add_${_component}")
set(CPKT_BUILD_DEPENDENCIES OFF)
if(CPKT_DEPENDENCY_PRODUCER AND _owner STREQUAL CPKT_GROUP)
set(CPKT_BUILD_DEPENDENCIES ON)
endif()
get_property(_before GLOBAL PROPERTY CPKT_DEPENDENCY_TARGETS)
cmake_language(CALL "${_function}")
get_property(_after GLOBAL PROPERTY CPKT_DEPENDENCY_TARGETS)
set(_component_targets "${_after}")
if(_before)
list(REMOVE_ITEM _component_targets ${_before})
endif()
set_property(GLOBAL PROPERTY "CPKT_PRODUCER_TARGETS_${_component}" "${_component_targets}")
if(_component_targets)
set(_remaining "${_component_targets}")
list(POP_BACK _remaining _last_project)
get_property(_complete GLOBAL PROPERTY "CPKT_COMPONENT_COMPLETE_${_component}")
set(_install_stamps "")
foreach(_project IN LISTS _remaining)
  ExternalProject_Get_Property(${_project} STAMP_DIR)
  list(APPEND _install_stamps "${STAMP_DIR}/${_project}-done")
endforeach()
ExternalProject_Add_Step(${_last_project} component-complete
  COMMAND "${CMAKE_COMMAND}" -E touch "${_complete}"
  DEPENDEES install DEPENDS ${_install_stamps}
  BYPRODUCTS "${_complete}")

add_custom_target(cpkt_deps_${_component} DEPENDS ${_component_targets})
list(APPEND _all_dependency_targets ${_component_targets})
endif()
endforeach()
if(CPKT_DEPENDENCY_PRODUCER)
add_custom_target(cpkt_deps_all DEPENDS ${_all_dependency_targets})
add_custom_target(cpkt_deps DEPENDS cpkt_deps_all)
endif()
endfunction()
