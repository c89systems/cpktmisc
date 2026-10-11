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
    -DOpenSSL_DIR=${CPKT_CORE_PREFIX}/lib/cmake/OpenSSL
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
          "${CPKT_CORE_PREFIX}/share/cpkt/mqtt-c"
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
          "${CPKT_CORE_PREFIX}/share/cpkt/mqtt-c"
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
