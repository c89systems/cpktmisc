function(cpkt_add_libpng)
cpkt_component_producer_prerequisites(producer_prerequisites libpng cpkt_zlib_project)
set(project_name cpkt_libpng_project)
set(prefix_dir "${CPKT_DEPENDENCY_BUILD_ROOT}/libpng")
set(source_dir "${prefix_dir}/src")
set(build_dir "${prefix_dir}/build")
set(install_dir "${CPKT_EXTERNAL_ROOT}/libpng/install")
set(static_library "${install_dir}/lib/libpng16${CMAKE_STATIC_LIBRARY_SUFFIX}")
set(shared_library "${install_dir}/lib/libpng16${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(zlib_shared_library "${CPKT_CORE_PREFIX}/lib/libz${CMAKE_SHARED_LIBRARY_SUFFIX}")
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
        -DPNG_FRAMEWORK=OFF
        -DCMAKE_INSTALL_RPATH=${install_rpath}
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
        -DPNG_SHARED=ON
        -DPNG_STATIC=ON
        -DPNG_TESTS=OFF
        -DPNG_TOOLS=OFF
        -DPNG_HARDWARE_OPTIMIZATIONS=OFF
        -DPNG_LIBCONF_HEADER=${source_dir}/scripts/pnglibconf.h.prebuilt
        -DZLIB_ROOT=${CPKT_CORE_PREFIX}
        -DZLIB_INCLUDE_DIR=${CPKT_CORE_PREFIX}/include
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
