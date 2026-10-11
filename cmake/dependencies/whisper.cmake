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
