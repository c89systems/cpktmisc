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
