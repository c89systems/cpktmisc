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
set(shared_zlib_library "${CPKT_CORE_PREFIX}/lib/libz${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(static_zlib_library "${CPKT_CORE_PREFIX}/lib/libz${CMAKE_STATIC_LIBRARY_SUFFIX}")
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
        -DZLIB_INCLUDE_DIR=${CPKT_CORE_PREFIX}/include
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
        -DZLIB_INCLUDE_DIR=${CPKT_CORE_PREFIX}/include
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
