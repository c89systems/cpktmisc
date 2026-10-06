include(ExternalProject)
include("${CMAKE_CURRENT_LIST_DIR}/CpktVerifiedExternalProject.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/CpktDependencyArchiveCache.cmake")
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
cpkt_external_project_add(${_cpkt_ep_args})
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
      "You can prebuild it explicitly with scripts/deps.sh, but normal build/test/release entry points do not do that for you.")
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
foreach(_prefix_var IN ITEMS
      CPKT_ZLIB_PREFIX
      CPKT_OPENSSL_static_PREFIX
      CPKT_OPENSSL_shared_PREFIX
      CPKT_NGHTTP2_static_PREFIX
      CPKT_NGHTTP2_shared_PREFIX
      CPKT_LIBSSH2_PREFIX
      CPKT_LIBXML2_PREFIX
      CPKT_LUA_PREFIX
      CPKT_MQTTC_PREFIX
      CPKT_OPEN62541_PREFIX
      CPKT_KRB5_PREFIX
      CPKT_CYRUS_SASL_PREFIX
      CPKT_OPENLDAP_PREFIX
      CPKT_POSTGRESQL_PREFIX)
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
function(cpkt_add_libpng)
cpkt_component_producer_prerequisites(producer_prerequisites libpng cpkt_zlib_project)
set(project_name cpkt_libpng_project)
set(prefix_dir "${CPKT_DEPENDENCY_BUILD_ROOT}/libpng")
set(source_dir "${prefix_dir}/src")
set(build_dir "${prefix_dir}/build")
set(install_dir "${CPKT_EXTERNAL_ROOT}/libpng/install")
set(static_library "${install_dir}/lib/libpng16${CMAKE_STATIC_LIBRARY_SUFFIX}")
set(shared_library "${install_dir}/lib/libpng16${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(zlib_shared_library "${CPKT_ZLIB_PREFIX}/lib/libz${CMAKE_SHARED_LIBRARY_SUFFIX}")
cpkt_append_common_external_cmake_args(common_cmake_args)
cpkt_get_external_cmake_configure_command(cmake_configure_command)
cpkt_get_external_cmake_step_commands(cmake_build_command cmake_install_command)
cpkt_get_strip_dependency_install_command(strip_install_command "${install_dir}")
if(CPKT_BUILD_DEPENDENCIES)
file(MAKE_DIRECTORY "${install_dir}/include" "${install_dir}/lib")
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
set(install_rpath "@loader_path")
else()
set(install_rpath "$ORIGIN")
endif()
if(CPKT_BUILD_DEPENDENCIES)
cpkt_cached_external_project_add(${project_name}
      URL "https://github.com/pnggroup/libpng/archive/refs/tags/v${CPKT_LIBPNG_VERSION}.tar.gz"
      URL_HASH "SHA256=a9d4df463d36a6e5f9c29bd6f4967312d17e996c1854f3511f833924eb1993cf"
      DOWNLOAD_NAME "libpng-v${CPKT_LIBPNG_VERSION}.tar.gz"
      PREFIX "${prefix_dir}"
      DOWNLOAD_DIR "${CPKT_DOWNLOAD_ROOT}"
      SOURCE_DIR "${source_dir}"
      BINARY_DIR "${build_dir}"
      STAMP_DIR "${prefix_dir}/stamp"
      TMP_DIR "${prefix_dir}/tmp"
      TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_TIMEOUT}
      INACTIVITY_TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_INACTIVITY_TIMEOUT}
      DEPENDS ${producer_prerequisites}
      CONFIGURE_COMMAND ${cmake_configure_command}
        -DCMAKE_INSTALL_PREFIX=${install_dir}
        -DCMAKE_INSTALL_LIBDIR=lib
        -DCMAKE_BUILD_TYPE=${CPKT_DEPENDENCY_BUILD_TYPE}
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INSTALL_RPATH=${install_rpath}
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
        -DPNG_SHARED=ON
        -DPNG_STATIC=ON
        -DPNG_TESTS=OFF
        -DPNG_TOOLS=OFF
        -DPNG_HARDWARE_OPTIMIZATIONS=OFF
        -DPNG_LIBCONF_HEADER=${source_dir}/scripts/pnglibconf.h.prebuilt
        -DZLIB_ROOT=${CPKT_ZLIB_PREFIX}
        -DZLIB_INCLUDE_DIR=${CPKT_ZLIB_PREFIX}/include
        -DZLIB_LIBRARY=${zlib_shared_library}
        ${common_cmake_args}
      BUILD_COMMAND ${cmake_build_command}
      INSTALL_COMMAND ${cmake_install_command}
        COMMAND ${strip_install_command}
      BUILD_BYPRODUCTS "${static_library}" "${shared_library}"
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
endif()
add_library(cpkt::png_static STATIC IMPORTED GLOBAL)
set_target_properties(cpkt::png_static PROPERTIES
    IMPORTED_LOCATION "${static_library}"
    INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include"
    INTERFACE_LINK_LIBRARIES "cpkt::zlib_static;m")
add_library(cpkt::png_shared SHARED IMPORTED GLOBAL)
set_target_properties(cpkt::png_shared PROPERTIES
    IMPORTED_LOCATION "${shared_library}"
    INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include"
    INTERFACE_LINK_LIBRARIES "cpkt::zlib_shared;m")
if(CPKT_BUILD_DEPENDENCIES)
add_dependencies(cpkt::png_static ${project_name})
add_dependencies(cpkt::png_shared ${project_name})
cpkt_record_dependency_target(${project_name})
else()
cpkt_require_dependency_file("${static_library}" "libpng static library")
cpkt_require_dependency_file("${shared_library}" "libpng shared library")
cpkt_require_dependency_file("${install_dir}/include/png.h" "libpng public header")
endif()
set(CPKT_LIBPNG_PREFIX "${install_dir}" PARENT_SCOPE)
endfunction()
function(cpkt_add_libharu)
set(prefix_dir "${CPKT_DEPENDENCY_BUILD_ROOT}/libharu")
set(source_dir "${prefix_dir}/src")
set(install_dir "${CPKT_EXTERNAL_ROOT}/libharu/install")
set(shared_project cpkt_libharu_shared_project)
set(static_project cpkt_libharu_static_project)
set(shared_library "${install_dir}/lib/libhpdf${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(static_library "${install_dir}/lib/libhpdf${CMAKE_STATIC_LIBRARY_SUFFIX}")
cpkt_append_common_external_cmake_args(common_cmake_args)
cpkt_get_external_cmake_configure_command(cmake_configure_command)
cpkt_get_external_cmake_step_commands(cmake_build_command cmake_install_command)
cpkt_get_strip_dependency_install_command(strip_install_command "${install_dir}")
if(CPKT_BUILD_DEPENDENCIES)
file(MAKE_DIRECTORY "${install_dir}/include" "${install_dir}/lib")
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
set(install_rpath "@loader_path")
else()
set(install_rpath "$ORIGIN")
endif()
set(shared_png_library "${CPKT_LIBPNG_PREFIX}/lib/libpng16${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(static_png_library "${CPKT_LIBPNG_PREFIX}/lib/libpng16${CMAKE_STATIC_LIBRARY_SUFFIX}")
set(shared_zlib_library "${CPKT_ZLIB_PREFIX}/lib/libz${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(static_zlib_library "${CPKT_ZLIB_PREFIX}/lib/libz${CMAKE_STATIC_LIBRARY_SUFFIX}")
if(CPKT_BUILD_DEPENDENCIES)
cpkt_cached_external_project_add(${shared_project}
      URL "https://github.com/libharu/libharu/archive/refs/tags/v${CPKT_LIBHARU_VERSION}.tar.gz"
      URL_HASH "SHA256=ec8f327520d1d354ce58b5d2af75b64f380cddc522437c169463b39760921348"
      DOWNLOAD_NAME "libharu-v${CPKT_LIBHARU_VERSION}.tar.gz"
      PREFIX "${prefix_dir}/shared"
      DOWNLOAD_DIR "${CPKT_DOWNLOAD_ROOT}"
      SOURCE_DIR "${source_dir}"
      BINARY_DIR "${prefix_dir}/build-shared"
      STAMP_DIR "${prefix_dir}/stamp-shared"
      TMP_DIR "${prefix_dir}/tmp-shared"
      TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_TIMEOUT}
      INACTIVITY_TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_INACTIVITY_TIMEOUT}
      DEPENDS cpkt_libpng_project
      CONFIGURE_COMMAND ${cmake_configure_command}
        -DCMAKE_INSTALL_PREFIX=${install_dir}
        -DCMAKE_INSTALL_LIBDIR=lib
        -DCMAKE_BUILD_TYPE=${CPKT_DEPENDENCY_BUILD_TYPE}
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INSTALL_RPATH=${install_rpath}
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
        -DBUILD_SHARED_LIBS=ON
        -DLIBHPDF_EXAMPLES=OFF
        -DPNG_PNG_INCLUDE_DIR=${CPKT_LIBPNG_PREFIX}/include
        -DPNG_LIBRARY=${shared_png_library}
        -DZLIB_INCLUDE_DIR=${CPKT_ZLIB_PREFIX}/include
        -DZLIB_LIBRARY=${shared_zlib_library}
        ${common_cmake_args}
      BUILD_COMMAND ${cmake_build_command}
      INSTALL_COMMAND ${cmake_install_command}
        COMMAND ${strip_install_command}
      BUILD_BYPRODUCTS "${shared_library}"
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
cpkt_cached_external_project_add(${static_project}
      URL "https://github.com/libharu/libharu/archive/refs/tags/v${CPKT_LIBHARU_VERSION}.tar.gz"
      URL_HASH "SHA256=ec8f327520d1d354ce58b5d2af75b64f380cddc522437c169463b39760921348"
      DOWNLOAD_NAME "libharu-v${CPKT_LIBHARU_VERSION}.tar.gz"
      PREFIX "${prefix_dir}/static"
      DOWNLOAD_DIR "${CPKT_DOWNLOAD_ROOT}"
      SOURCE_DIR "${source_dir}"
      BINARY_DIR "${prefix_dir}/build-static"
      STAMP_DIR "${prefix_dir}/stamp-static"
      TMP_DIR "${prefix_dir}/tmp-static"
      TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_TIMEOUT}
      INACTIVITY_TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_INACTIVITY_TIMEOUT}
      DEPENDS ${shared_project}
      CONFIGURE_COMMAND ${cmake_configure_command}
        -DCMAKE_INSTALL_PREFIX=${install_dir}
        -DCMAKE_INSTALL_LIBDIR=lib
        -DCMAKE_BUILD_TYPE=${CPKT_DEPENDENCY_BUILD_TYPE}
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=OFF
        -DLIBHPDF_EXAMPLES=OFF
        -DPNG_PNG_INCLUDE_DIR=${CPKT_LIBPNG_PREFIX}/include
        -DPNG_LIBRARY=${static_png_library}
        -DZLIB_INCLUDE_DIR=${CPKT_ZLIB_PREFIX}/include
        -DZLIB_LIBRARY=${static_zlib_library}
        ${common_cmake_args}
      BUILD_COMMAND ${cmake_build_command}
      INSTALL_COMMAND ${cmake_install_command}
      BUILD_BYPRODUCTS "${static_library}"
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
endif()
add_library(cpkt::haru_static STATIC IMPORTED GLOBAL)
set_target_properties(cpkt::haru_static PROPERTIES
    IMPORTED_LOCATION "${static_library}"
    INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include"
    INTERFACE_LINK_LIBRARIES "cpkt::png_static;cpkt::zlib_static")
add_library(cpkt::haru_shared SHARED IMPORTED GLOBAL)
set_target_properties(cpkt::haru_shared PROPERTIES
    IMPORTED_LOCATION "${shared_library}"
    INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include"
    INTERFACE_LINK_LIBRARIES "cpkt::png_shared;cpkt::zlib_shared")
if(CPKT_BUILD_DEPENDENCIES)
add_dependencies(cpkt::haru_static ${static_project})
add_dependencies(cpkt::haru_shared ${shared_project})
cpkt_record_dependency_target(${static_project})
else()
cpkt_require_dependency_file("${static_library}" "libHaru static library")
cpkt_require_dependency_file("${shared_library}" "libHaru shared library")
cpkt_require_dependency_file("${install_dir}/include/hpdf.h" "libHaru public header")
endif()
set(CPKT_LIBHARU_PREFIX "${install_dir}" PARENT_SCOPE)
endfunction()
function(cpkt_add_miniaudio)
set(project_name "cpkt_miniaudio_project")
set(prefix_dir "${CPKT_DEPENDENCY_BUILD_ROOT}/miniaudio")
set(source_dir "${prefix_dir}/src")
set(build_dir "${prefix_dir}/build")
set(install_dir "${CPKT_EXTERNAL_ROOT}/miniaudio/install")
set(stamp_dir "${prefix_dir}/stamp")
set(tmp_dir "${prefix_dir}/tmp")
cpkt_get_strip_dependency_install_command(strip_install_command "${install_dir}")
if(CPKT_BUILD_DEPENDENCIES)
file(MAKE_DIRECTORY "${install_dir}/include/miniaudio" "${install_dir}/lib")
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
set(miniaudio_shared_library "${install_dir}/lib/libminiaudio${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(miniaudio_shared_link_flags
      -dynamiclib
      -Wl,-install_name,@rpath/libminiaudio${CMAKE_SHARED_LIBRARY_SUFFIX}
    )
if(CMAKE_LINKER)
list(APPEND miniaudio_shared_link_flags "--ld-path=${CMAKE_LINKER}")
endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
set(miniaudio_shared_library "${install_dir}/lib/libminiaudio${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(miniaudio_shared_link_flags
      -shared
      -Wl,--enable-new-dtags
      -Wl,-rpath,\$ORIGIN
      -Wl,-soname,libminiaudio${CMAKE_SHARED_LIBRARY_SUFFIX}
    )
else()
set(miniaudio_shared_library "${install_dir}/lib/libminiaudio${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(miniaudio_shared_link_flags -shared)
endif()
set(miniaudio_static_library "${install_dir}/lib/libminiaudio${CMAKE_STATIC_LIBRARY_SUFFIX}")
cpkt_get_external_c_flags(miniaudio_external_cflags)
separate_arguments(miniaudio_compile_flags NATIVE_COMMAND "${miniaudio_external_cflags}")
list(APPEND miniaudio_compile_flags
    -fPIC
    -DMA_NO_RESOURCE_MANAGER
    -DMA_NO_NODE_GRAPH
    -DMA_NO_ENGINE
    -DMA_NO_GENERATION
  )
set(miniaudio_object "${build_dir}/miniaudio.c.o")
set(miniaudio_link_libraries -lm -pthread)
if(CMAKE_DL_LIBS)
list(APPEND miniaudio_link_libraries "-l${CMAKE_DL_LIBS}")
endif()
set(miniaudio_env_args "")
cpkt_append_pinned_external_toolchain_env_args(miniaudio_env_args)
if(CPKT_BUILD_DEPENDENCIES)
cpkt_cached_external_project_add(${project_name}
      URL "https://github.com/mackron/miniaudio/archive/refs/tags/${CPKT_MINIAUDIO_VERSION}.tar.gz"
      URL_HASH "SHA256=b900edcffe979816e2560a0580b9b1216d674b4f17fbadeca8f777a7f8ab0274"
      DOWNLOAD_NAME "miniaudio-${CPKT_MINIAUDIO_VERSION}.tar.gz"
      PREFIX "${prefix_dir}"
      DOWNLOAD_DIR "${CPKT_DOWNLOAD_ROOT}"
      SOURCE_DIR "${source_dir}"
      BINARY_DIR "${build_dir}"
      STAMP_DIR "${stamp_dir}"
      TMP_DIR "${tmp_dir}"
      TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_TIMEOUT}
      INACTIVITY_TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_INACTIVITY_TIMEOUT}
      CONFIGURE_COMMAND
        ${CMAKE_COMMAND} -E make_directory
          "${build_dir}"
          "${install_dir}/include/miniaudio"
          "${install_dir}/lib"
      BUILD_COMMAND
        ${CMAKE_COMMAND} -E env ${miniaudio_env_args}
          ${CMAKE_C_COMPILER}
          ${miniaudio_compile_flags}
          -c "${source_dir}/miniaudio.c"
          -o "${miniaudio_object}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${miniaudio_static_library}"
        COMMAND ${CMAKE_AR} qc "${miniaudio_static_library}" "${miniaudio_object}"
        COMMAND ${CMAKE_RANLIB} "${miniaudio_static_library}"
        COMMAND ${CMAKE_COMMAND} -E rm -f "${miniaudio_shared_library}"
        COMMAND ${CMAKE_COMMAND} -E env ${miniaudio_env_args}
          ${CMAKE_C_COMPILER}
          ${miniaudio_shared_link_flags}
          -o "${miniaudio_shared_library}"
          "${miniaudio_object}"
          ${miniaudio_link_libraries}
      INSTALL_COMMAND
        ${CMAKE_COMMAND} -E copy_if_different
          "${source_dir}/miniaudio.h"
          "${install_dir}/include/miniaudio/miniaudio.h"
        COMMAND ${strip_install_command}
      BUILD_BYPRODUCTS
        "${miniaudio_static_library}"
        "${miniaudio_shared_library}"
      BUILD_IN_SOURCE 0
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
endif()
add_library(cpkt::miniaudio_static STATIC IMPORTED GLOBAL)
set_target_properties(cpkt::miniaudio_static
    PROPERTIES
      IMPORTED_LOCATION "${miniaudio_static_library}"
      INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include/miniaudio"
      INTERFACE_LINK_LIBRARIES "m;Threads::Threads"
  )
add_library(cpkt::miniaudio_shared SHARED IMPORTED GLOBAL)
set_target_properties(cpkt::miniaudio_shared
    PROPERTIES
      IMPORTED_LOCATION "${miniaudio_shared_library}"
      INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include/miniaudio"
      INTERFACE_LINK_LIBRARIES "m;Threads::Threads"
  )
if(CPKT_BUILD_DEPENDENCIES)
add_dependencies(cpkt::miniaudio_static ${project_name})
add_dependencies(cpkt::miniaudio_shared ${project_name})
cpkt_record_dependency_target(${project_name})
else()
cpkt_require_dependency_file("${miniaudio_static_library}" "miniaudio static library")
cpkt_require_dependency_file("${miniaudio_shared_library}" "miniaudio shared library")
cpkt_require_dependency_file("${install_dir}/include/miniaudio/miniaudio.h" "miniaudio header")
endif()
endfunction()
function(cpkt_add_whisper)
if(NOT CPKT_SUS_CPU_ONLY)
message(FATAL_ERROR "cpkt_sus currently supports only CPU-only whisper.cpp dependency builds")
endif()
set(project_name_shared "cpkt_whisper_shared_project")
set(project_name_static "cpkt_whisper_static_project")
set(prefix_dir "${CPKT_DEPENDENCY_BUILD_ROOT}/whisper")
set(source_dir_shared "${prefix_dir}/src-shared")
set(source_dir_static "${prefix_dir}/src-static")
set(shared_build_dir "${prefix_dir}/build-shared")
set(static_build_dir "${prefix_dir}/build-static")
set(install_dir "${CPKT_EXTERNAL_ROOT}/whisper/install")
set(stamp_dir "${prefix_dir}/stamp")
set(tmp_dir "${prefix_dir}/tmp")
cpkt_append_common_external_cxx_cmake_args(common_cmake_args)
cpkt_get_external_cmake_step_commands(cmake_build_command cmake_install_command)
cpkt_get_strip_dependency_install_command(strip_install_command "${install_dir}")
if(CPKT_BUILD_DEPENDENCIES)
file(MAKE_DIRECTORY "${install_dir}/include" "${install_dir}/lib")
endif()
set(whisper_static_library "${install_dir}/lib/libwhisper${CMAKE_STATIC_LIBRARY_SUFFIX}")
set(whisper_shared_library "${install_dir}/lib/libwhisper${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(ggml_static_libraries
    "${install_dir}/lib/libggml${CMAKE_STATIC_LIBRARY_SUFFIX}"
    "${install_dir}/lib/libggml-base${CMAKE_STATIC_LIBRARY_SUFFIX}"
    "${install_dir}/lib/libggml-cpu${CMAKE_STATIC_LIBRARY_SUFFIX}")
set(ggml_shared_libraries
    "${install_dir}/lib/libggml${CMAKE_SHARED_LIBRARY_SUFFIX}"
    "${install_dir}/lib/libggml-base${CMAKE_SHARED_LIBRARY_SUFFIX}"
    "${install_dir}/lib/libggml-cpu${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(whisper_install_rpath "")
set(whisper_shared_linker_flags "")
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
set(whisper_install_rpath "$ORIGIN")
if(CMAKE_CXX_COMPILER_ID MATCHES "^(GNU|Clang)$")
set(whisper_shared_linker_flags "-static-libstdc++ -static-libgcc")
endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
set(whisper_install_rpath "@loader_path")
endif()
set(whisper_common_cmake_args
    -DCMAKE_INSTALL_PREFIX=${install_dir}
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_BUILD_TYPE=${CPKT_DEPENDENCY_BUILD_TYPE}
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DCMAKE_INSTALL_RPATH=${whisper_install_rpath}
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
    -DCMAKE_BUILD_RPATH=
    -DCMAKE_SKIP_INSTALL_RPATH=OFF
    -DCMAKE_SHARED_LINKER_FLAGS=${whisper_shared_linker_flags}
    -DCMAKE_MODULE_LINKER_FLAGS=${whisper_shared_linker_flags}
    -DWHISPER_BUILD_TESTS=OFF
    -DWHISPER_BUILD_EXAMPLES=OFF
    -DWHISPER_BUILD_SERVER=OFF
    -DWHISPER_CURL=OFF
    -DWHISPER_SDL2=OFF
    -DWHISPER_COREML=OFF
    -DWHISPER_COREML_ALLOW_FALLBACK=OFF
    -DWHISPER_OPENVINO=OFF
    -DWHISPER_ALL_WARNINGS=OFF
    -DWHISPER_ALL_WARNINGS_3RD_PARTY=OFF
    -DWHISPER_FATAL_WARNINGS=OFF
    -DGGML_NATIVE=OFF
    -DGGML_OPENMP=OFF
    -DGGML_METAL=OFF
    -DGGML_BLAS=OFF
    -DGGML_ACCELERATE=OFF
    -DGGML_CUDA=OFF
    -DGGML_HIP=OFF
    -DGGML_VULKAN=OFF
    -DGGML_OPENCL=OFF
    -DGGML_SYCL=OFF
    -DGGML_RPC=OFF
    -DGGML_BACKEND_DL=OFF
    -DGGML_CPU_ALL_VARIANTS=OFF
    -DGGML_CCACHE=OFF
    ${common_cmake_args}
  )
if(CPKT_BUILD_DEPENDENCIES)
cpkt_cached_external_project_add(${project_name_shared}
      URL "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/${CPKT_WHISPER_VERSION}.tar.gz"
      URL_HASH "SHA256=57e280cee375ab02425b806ad5146b99f6eb9357e3c2b31357c8a6af2e2e44ae"
      DOWNLOAD_NAME "whisper.cpp-${CPKT_WHISPER_VERSION}.tar.gz"
      PREFIX "${prefix_dir}"
      DOWNLOAD_DIR "${CPKT_DOWNLOAD_ROOT}"
      SOURCE_DIR "${source_dir_shared}"
      BINARY_DIR "${shared_build_dir}"
      STAMP_DIR "${stamp_dir}/shared"
      TMP_DIR "${tmp_dir}"
      TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_TIMEOUT}
      INACTIVITY_TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_INACTIVITY_TIMEOUT}
      PATCH_COMMAND
        ${CMAKE_COMMAND}
          -DWHISPER_SOURCE_DIR=<SOURCE_DIR>
          -P ${CMAKE_SOURCE_DIR}/cmake/patch_whisper_buildinfo.cmake
        COMMAND ${CMAKE_COMMAND}
          -DCPKT_PATCH_WORKING_DIRECTORY=<SOURCE_DIR>
          -DCPKT_PATCH_SERIES=${CMAKE_SOURCE_DIR}/cmake/patches/whisper.series
          -P ${CMAKE_SOURCE_DIR}/cmake/apply_patch_series.cmake
      CMAKE_ARGS
        -DBUILD_SHARED_LIBS=ON
        ${whisper_common_cmake_args}
      BUILD_COMMAND ${cmake_build_command}
      INSTALL_COMMAND ${cmake_install_command}
      BUILD_BYPRODUCTS
        "${whisper_shared_library}"
        ${ggml_shared_libraries}
      BUILD_IN_SOURCE 0
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
cpkt_cached_external_project_add(${project_name_static}
      URL "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/${CPKT_WHISPER_VERSION}.tar.gz"
      URL_HASH "SHA256=57e280cee375ab02425b806ad5146b99f6eb9357e3c2b31357c8a6af2e2e44ae"
      DOWNLOAD_NAME "whisper.cpp-${CPKT_WHISPER_VERSION}.tar.gz"
      PREFIX "${prefix_dir}"
      DOWNLOAD_DIR "${CPKT_DOWNLOAD_ROOT}"
      SOURCE_DIR "${source_dir_static}"
      BINARY_DIR "${static_build_dir}"
      STAMP_DIR "${stamp_dir}/static"
      TMP_DIR "${tmp_dir}"
      TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_TIMEOUT}
      INACTIVITY_TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_INACTIVITY_TIMEOUT}
      PATCH_COMMAND
        ${CMAKE_COMMAND}
          -DWHISPER_SOURCE_DIR=<SOURCE_DIR>
          -P ${CMAKE_SOURCE_DIR}/cmake/patch_whisper_buildinfo.cmake
        COMMAND ${CMAKE_COMMAND}
          -DCPKT_PATCH_WORKING_DIRECTORY=<SOURCE_DIR>
          -DCPKT_PATCH_SERIES=${CMAKE_SOURCE_DIR}/cmake/patches/whisper.series
          -P ${CMAKE_SOURCE_DIR}/cmake/apply_patch_series.cmake
      CMAKE_ARGS
        -DBUILD_SHARED_LIBS=OFF
        ${whisper_common_cmake_args}
      BUILD_COMMAND ${cmake_build_command}
      INSTALL_COMMAND ${cmake_install_command}
        COMMAND ${strip_install_command}
      BUILD_BYPRODUCTS
        "${whisper_static_library}"
        ${ggml_static_libraries}
      BUILD_IN_SOURCE 0
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
cpkt_order_shared_install(${project_name_shared} ${project_name_static})
endif()
add_library(cpkt::whisper_static STATIC IMPORTED GLOBAL)
set_target_properties(cpkt::whisper_static
    PROPERTIES
      IMPORTED_LOCATION "${whisper_static_library}"
      INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include"
      INTERFACE_LINK_LIBRARIES "${ggml_static_libraries};Threads::Threads;m"
  )
add_library(cpkt::whisper_shared SHARED IMPORTED GLOBAL)
set_target_properties(cpkt::whisper_shared
    PROPERTIES
      IMPORTED_LOCATION "${whisper_shared_library}"
      INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include"
      INTERFACE_LINK_LIBRARIES "${ggml_shared_libraries};Threads::Threads"
  )
if(CPKT_BUILD_DEPENDENCIES)
add_dependencies(cpkt::whisper_static ${project_name_static})
add_dependencies(cpkt::whisper_shared ${project_name_shared})
cpkt_record_dependency_target(${project_name_static})
cpkt_record_dependency_target(${project_name_shared})
else()
cpkt_require_dependency_file("${whisper_static_library}" "whisper.cpp static library")
cpkt_require_dependency_file("${whisper_shared_library}" "whisper.cpp shared library")
cpkt_require_dependency_file("${install_dir}/include/whisper.h" "whisper.cpp header")
endif()
endfunction()
function(cpkt_add_open62541)
cpkt_component_producer_prerequisites(producer_prerequisites open62541 cpkt_openssl_project cpkt_mqttc_project)
set(project_name_shared "cpkt_open62541_shared_project")
set(project_name_static "cpkt_open62541_static_project")
set(prefix_dir "${CPKT_DEPENDENCY_BUILD_ROOT}/open62541")
set(source_dir_shared "${prefix_dir}/src-shared")
set(source_dir_static "${prefix_dir}/src-static")
set(shared_build_dir "${prefix_dir}/build-shared")
set(static_build_dir "${prefix_dir}/build-static")
set(install_dir "${CPKT_EXTERNAL_ROOT}/open62541/install")
set(stamp_dir "${prefix_dir}/stamp")
set(tmp_dir "${prefix_dir}/tmp")
cpkt_append_common_external_cmake_args(common_cmake_args)
cpkt_get_external_cmake_step_commands(cmake_build_command cmake_install_command)
cpkt_get_strip_dependency_install_command(strip_install_command "${install_dir}")
if(CPKT_BUILD_DEPENDENCIES)
file(MAKE_DIRECTORY "${install_dir}/include" "${install_dir}/lib")
endif()
set(open62541_static_library "${install_dir}/lib/libopen62541${CMAKE_STATIC_LIBRARY_SUFFIX}")
set(open62541_static_system_libs "m")
set(open62541_static_pc_private_libs "-lm")
set(open62541_interface_compile_definitions "_GNU_SOURCE")
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
set(open62541_shared_library "${install_dir}/lib/libopen62541.${CPKT_OPEN62541_VERSION}${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(open62541_install_rpath "@loader_path")
set(open62541_platform_cmake_args "")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
set(open62541_shared_library "${install_dir}/lib/libopen62541${CMAKE_SHARED_LIBRARY_SUFFIX}.${CPKT_OPEN62541_VERSION}")
set(open62541_install_rpath "$ORIGIN")
set(open62541_platform_cmake_args
      -DCMAKE_SHARED_LINKER_FLAGS=-Wl,--enable-new-dtags)
list(APPEND open62541_static_system_libs rt)
string(APPEND open62541_static_pc_private_libs " -lrt")
else()
set(open62541_shared_library "${install_dir}/lib/libopen62541${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(open62541_install_rpath "")
set(open62541_platform_cmake_args "")
endif()
set(open62541_common_cmake_args
    -DCMAKE_INSTALL_PREFIX=${install_dir}
    -DCMAKE_INSTALL_LIBDIR=lib
    -DCMAKE_BUILD_TYPE=${CPKT_DEPENDENCY_BUILD_TYPE}
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON
    -DCMAKE_INSTALL_RPATH=${open62541_install_rpath}
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
    -DCMAKE_BUILD_RPATH=
    -DCMAKE_SKIP_INSTALL_RPATH=OFF
    ${open62541_platform_cmake_args}
    -DOPEN62541_VERSION=v${CPKT_OPEN62541_VERSION}
    -DGIT_EXECUTABLE=GIT_EXECUTABLE-NOTFOUND
    -DUA_ARCHITECTURE=posix
    -DUA_NAMESPACE_ZERO=REDUCED
    -DUA_ENABLE_AMALGAMATION=OFF
    -DUA_ENABLE_ENCRYPTION=OPENSSL
    -DUA_ENABLE_MQTT=ON
    -DUA_ENABLE_JSON_ENCODING=ON
    -DUA_ENABLE_XML_ENCODING=ON
    -DUA_ENABLE_DIAGNOSTICS=ON
    -DUA_ENABLE_METHODCALLS=ON
    -DUA_ENABLE_SUBSCRIPTIONS=ON
    -DUA_ENABLE_SUBSCRIPTIONS_EVENTS=ON
    -DUA_ENABLE_HISTORIZING=ON
    -DUA_ENABLE_DISCOVERY=ON
    -DUA_ENABLE_DISCOVERY_MULTICAST=OFF
    -DUA_ENABLE_NODEMANAGEMENT=ON
    -DUA_ENABLE_PUBSUB=ON
    -DUA_ENABLE_PUBSUB_INFORMATIONMODEL=ON
    -DUA_ENABLE_TYPEDESCRIPTION=ON
    -DUA_ENABLE_STATUSCODE_DESCRIPTIONS=ON
    -DUA_BUILD_EXAMPLES=OFF
    -DUA_BUILD_TOOLS=OFF
    -DUA_BUILD_UNIT_TESTS=OFF
    -DOpenSSL_DIR=${CPKT_OPENSSL_static_PREFIX}/lib/cmake/OpenSSL
    ${common_cmake_args}
  )
if(CPKT_BUILD_DEPENDENCIES)
cpkt_cached_external_project_add(${project_name_shared}
      URL "https://github.com/open62541/open62541/archive/refs/tags/v${CPKT_OPEN62541_VERSION}.tar.gz"
      URL_HASH "SHA256=cf7951baf253c0537b3397e4ce3ff13930542abcb6ffc3b9cb082af88f95c300"
      DOWNLOAD_NAME "open62541-${CPKT_OPEN62541_VERSION}.tar.gz"
      PREFIX "${prefix_dir}"
      DOWNLOAD_DIR "${CPKT_DOWNLOAD_ROOT}"
      SOURCE_DIR "${source_dir_shared}"
      BINARY_DIR "${shared_build_dir}"
      STAMP_DIR "${stamp_dir}/shared"
      TMP_DIR "${tmp_dir}"
      TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_TIMEOUT}
      INACTIVITY_TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_INACTIVITY_TIMEOUT}
      DEPENDS ${producer_prerequisites}
      PATCH_COMMAND
        ${CMAKE_COMMAND} -E copy_directory
          "${CPKT_MQTTC_SOURCE_DIR}"
          "${source_dir_shared}/deps/mqtt-c"
        COMMAND ${CMAKE_COMMAND}
          -DCPKT_PATCH_WORKING_DIRECTORY=${source_dir_shared}
          -DCPKT_PATCH_SERIES=${CMAKE_SOURCE_DIR}/vendor/open62541/patches/series
          -P ${CMAKE_SOURCE_DIR}/cmake/apply_patch_series.cmake
      CMAKE_ARGS
        -DBUILD_SHARED_LIBS=ON
        -DOPENSSL_USE_STATIC_LIBS:BOOL=OFF
        -DUA_FILE_MQTT=${source_dir_shared}/deps/mqtt-c/src/mqtt.c
        ${open62541_common_cmake_args}
      BUILD_COMMAND ${cmake_build_command}
      INSTALL_COMMAND ${cmake_install_command}
      BUILD_BYPRODUCTS "${open62541_shared_library}"
      BUILD_IN_SOURCE 0
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
cpkt_cached_external_project_add(${project_name_static}
      URL "https://github.com/open62541/open62541/archive/refs/tags/v${CPKT_OPEN62541_VERSION}.tar.gz"
      URL_HASH "SHA256=cf7951baf253c0537b3397e4ce3ff13930542abcb6ffc3b9cb082af88f95c300"
      DOWNLOAD_NAME "open62541-${CPKT_OPEN62541_VERSION}.tar.gz"
      PREFIX "${prefix_dir}"
      DOWNLOAD_DIR "${CPKT_DOWNLOAD_ROOT}"
      SOURCE_DIR "${source_dir_static}"
      BINARY_DIR "${static_build_dir}"
      STAMP_DIR "${stamp_dir}/static"
      TMP_DIR "${tmp_dir}"
      TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_TIMEOUT}
      INACTIVITY_TIMEOUT ${CPKT_DEPENDENCY_DOWNLOAD_INACTIVITY_TIMEOUT}
      DEPENDS ${producer_prerequisites}
      PATCH_COMMAND
        ${CMAKE_COMMAND} -E copy_directory
          "${CPKT_MQTTC_SOURCE_DIR}"
          "${source_dir_static}/deps/mqtt-c"
        COMMAND ${CMAKE_COMMAND}
          -DCPKT_PATCH_WORKING_DIRECTORY=${source_dir_static}
          -DCPKT_PATCH_SERIES=${CMAKE_SOURCE_DIR}/vendor/open62541/patches/series
          -P ${CMAKE_SOURCE_DIR}/cmake/apply_patch_series.cmake
      CMAKE_ARGS
        -DBUILD_SHARED_LIBS=OFF
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION:BOOL=OFF
        -DOPENSSL_USE_STATIC_LIBS:BOOL=ON
        -DUA_FILE_MQTT=${source_dir_static}/deps/mqtt-c/src/mqtt.c
        ${open62541_common_cmake_args}
      BUILD_COMMAND ${cmake_build_command}
      INSTALL_COMMAND ${cmake_install_command}
        COMMAND ${strip_install_command}
      BUILD_BYPRODUCTS "${open62541_static_library}"
      BUILD_IN_SOURCE 0
      DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
endif()
add_library(cpkt::open62541_static STATIC IMPORTED GLOBAL)
set_target_properties(cpkt::open62541_static
    PROPERTIES
      IMPORTED_LOCATION "${open62541_static_library}"
      INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include"
      INTERFACE_LINK_LIBRARIES "cpkt::openssl_ssl_static;cpkt::openssl_crypto_static;${open62541_static_system_libs}"
      INTERFACE_COMPILE_DEFINITIONS "${open62541_interface_compile_definitions}"
  )
add_library(cpkt::open62541_shared SHARED IMPORTED GLOBAL)
set_target_properties(cpkt::open62541_shared
    PROPERTIES
      IMPORTED_LOCATION "${open62541_shared_library}"
      INTERFACE_INCLUDE_DIRECTORIES "${install_dir}/include"
      INTERFACE_LINK_LIBRARIES "cpkt::openssl_ssl_shared;cpkt::openssl_crypto_shared"
      INTERFACE_COMPILE_DEFINITIONS "${open62541_interface_compile_definitions}"
  )
if(CPKT_BUILD_DEPENDENCIES)
add_dependencies(cpkt::open62541_static ${project_name_static})
add_dependencies(cpkt::open62541_shared ${project_name_shared})
cpkt_record_dependency_target(${project_name_static})
cpkt_record_dependency_target(${project_name_shared})
else()
cpkt_require_dependency_file("${open62541_static_library}" "open62541 static library")
cpkt_require_dependency_file("${open62541_shared_library}" "open62541 shared library")
cpkt_require_dependency_file("${install_dir}/include/open62541/server.h" "open62541 server header")
cpkt_require_dependency_file("${install_dir}/include/open62541/client.h" "open62541 client header")
endif()
endfunction()
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
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyContract.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyArchiveCache.cmake"
    RECIPE_FUNCTIONS cpkt_add_libpng)
cpkt_prepare_dependency_component(
    NAME libharu
    BUILD_ROOT "${CPKT_DEPENDENCY_BUILD_ROOT}/libharu"
    INSTALL_ROOT "${CPKT_EXTERNAL_ROOT}/libharu/install"
    VARIABLES CPKT_LIBHARU_VERSION
    DEPENDS libpng zlib
    INPUT_FILES
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyContract.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyArchiveCache.cmake"
    RECIPE_FUNCTIONS cpkt_add_libharu)
cpkt_prepare_dependency_component(
    NAME miniaudio
    BUILD_ROOT "${CPKT_DEPENDENCY_BUILD_ROOT}/miniaudio"
    INSTALL_ROOT "${CPKT_EXTERNAL_ROOT}/miniaudio/install"
    VARIABLES CPKT_MINIAUDIO_VERSION
    INPUT_FILES
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyContract.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyArchiveCache.cmake"
    RECIPE_FUNCTIONS cpkt_add_miniaudio)
cpkt_prepare_dependency_component(
    NAME whisper
    BUILD_ROOT "${CPKT_DEPENDENCY_BUILD_ROOT}/whisper"
    INSTALL_ROOT "${CPKT_EXTERNAL_ROOT}/whisper/install"
    VARIABLES CPKT_WHISPER_VERSION CPKT_SUS_CPU_ONLY
    INPUT_FILES
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyContract.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/CpktDependencyArchiveCache.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/patch_whisper_buildinfo.cmake"
      "${CMAKE_SOURCE_DIR}/cmake/patches/whisper.series"
      "${CMAKE_SOURCE_DIR}/cmake/patches/whisper_ggml_validation_logging.patch"
    RECIPE_FUNCTIONS cpkt_order_shared_install cpkt_add_whisper)
cpkt_prepare_dependency_component(
    NAME open62541
    BUILD_ROOT "${CPKT_DEPENDENCY_BUILD_ROOT}/open62541"
    INSTALL_ROOT "${CPKT_EXTERNAL_ROOT}/open62541/install"
    VARIABLES CPKT_OPEN62541_VERSION CPKT_OPEN62541_PATCHSET
    DEPENDS openssl mqttc
    INPUT_FILES
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
      "${CMAKE_SOURCE_DIR}/vendor/open62541/patches/0028-keep-disabled-lock-assert-warning-clean.patch"
    RECIPE_FUNCTIONS cpkt_add_open62541)
set(_all_dependency_targets "")
foreach(_component IN LISTS CPKT_ACTIVE_COMPONENTS)
    string(JSON _external ERROR_VARIABLE _missing GET "${CPKT_INVENTORY}" components "${_component}" external)
    if(NOT _missing)
      continue()
    endif()
string(JSON _owner GET "${CPKT_INVENTORY}" components "${_component}" group)
string(REPLACE "-" "_" _function "cpkt_add_${_component}")
set(CPKT_BUILD_DEPENDENCIES OFF)
if(CPKT_DEPENDENCY_PRODUCER AND _owner STREQUAL CPKT_GROUP)
set(CPKT_BUILD_DEPENDENCIES ON)
endif()
if(NOT CPKT_BUILD_DEPENDENCIES)
execute_process(COMMAND "${CPKT_HOST_PYTHON_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/cpkt_receipt_cli.py"
        --root "${CMAKE_SOURCE_DIR}" --group "${CPKT_GROUP}" --target "${CPKT_TARGET_ID}"
        --component "${_component}" --preset "$ENV{CPKT_PRESET}"
        RESULT_VARIABLE _receipt_status)
if(NOT _receipt_status EQUAL 0)
message(FATAL_ERROR "Unverified dependency import: ${_component}")
endif()
endif()
set(CPKT_VERIFIED_COMPONENT "")
set(CPKT_VERIFIED_COMPONENT_DEPENDS "")
get_property(_verified GLOBAL PROPERTY "CPKT_VERIFIED_COMPONENT_${_component}")
if(CPKT_BUILD_DEPENDENCIES AND _verified)
set(CPKT_VERIFIED_COMPONENT "${_component}")
string(JSON _directory GET "${CPKT_INVENTORY}" components "${_component}" directory)
set(CPKT_VERIFIED_COMPONENT_INSTALL "${CPKT_EXTERNAL_ROOT}/${_directory}/install")
string(JSON _count LENGTH "${CPKT_INVENTORY}" components "${_component}" dependencies)
if(_count GREATER 0)
math(EXPR _last "${_count} - 1")
foreach(_index RANGE 0 ${_last})
string(JSON _dependency GET "${CPKT_INVENTORY}" components "${_component}" dependencies ${_index})
if(TARGET "cpkt_deps_${_dependency}")
list(APPEND CPKT_VERIFIED_COMPONENT_DEPENDS "cpkt_deps_${_dependency}")
endif()
endforeach()
endif()
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
if(NOT CPKT_VERIFIED_COMPONENT)
ExternalProject_Add_Step(${_last_project} cpkt-receipt
        COMMAND "${CPKT_HOST_PYTHON_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/cpkt_receipt_cli.py"
          --root "${CMAKE_SOURCE_DIR}" --group "${CPKT_GROUP}" --target "${CPKT_TARGET_ID}"
          --component "${_component}" --publish
        DEPENDEES install DEPENDS ${_remaining}
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}")
endif()
add_custom_target(cpkt_deps_${_component} DEPENDS ${_component_targets})
list(APPEND _all_dependency_targets ${_component_targets})
endif()
endforeach()
if(CPKT_DEPENDENCY_PRODUCER)
add_custom_target(cpkt_deps_all DEPENDS ${_all_dependency_targets})
add_custom_target(cpkt_deps DEPENDS cpkt_deps_all)
endif()
endfunction()
