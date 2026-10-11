# Upstream projects remain the producers; these helpers declare native edges.
function(cpkt_codec_import name library)
  set(prefix "${CPKT_EXTERNAL_ROOT}/${name}/install")
  foreach(kind static shared)
    if(kind STREQUAL "static")
      set(suffix "${CMAKE_STATIC_LIBRARY_SUFFIX}")
      set(type STATIC)
    else()
      set(suffix "${CMAKE_SHARED_LIBRARY_SUFFIX}")
      set(type SHARED)
    endif()
    add_library(cpkt::${name}_${kind} ${type} IMPORTED GLOBAL)
    set_target_properties(cpkt::${name}_${kind} PROPERTIES
      IMPORTED_LOCATION "${prefix}/lib/lib${library}${suffix}"
      INTERFACE_INCLUDE_DIRECTORIES "${prefix}/include")
    if(CPKT_BUILD_DEPENDENCIES)
      get_property(projects GLOBAL PROPERTY "CPKT_CODEC_PROJECTS_${name}")
      add_dependencies(cpkt::${name}_${kind} ${projects})
    else()
      cpkt_require_dependency_file("${prefix}/lib/lib${library}${suffix}" "${name} ${kind} library")
    endif()
  endforeach()
  set(CPKT_${name}_PREFIX "${prefix}" PARENT_SCOPE)
endfunction()

function(cpkt_codec_cmake name url hash library)
  cmake_parse_arguments(recipe "DUAL" "SOURCE_SUBDIR;OWNED_SOURCE" "OPTIONS;INSTALL_HEADERS" ${ARGN})
  cpkt_component_producer_prerequisites(prerequisites "${name}")
  set(root "${CPKT_DEPENDENCY_BUILD_ROOT}/${name}")
  set(prefix "${CPKT_EXTERNAL_ROOT}/${name}/install")
  set(variants both)
  if(recipe_DUAL)
    set(variants static shared)
  endif()
  cpkt_append_common_external_cmake_args(common)
  # CMake 4 still builds the pinned projects' declared older policies.
  list(APPEND common -DCMAKE_POLICY_VERSION_MINIMUM=3.5)
  cpkt_get_external_cmake_configure_command(configure)
  cpkt_get_external_cmake_step_commands(build install)
  cpkt_get_strip_dependency_install_command(strip "${prefix}")
  set(projects "")
  foreach(variant IN LISTS variants)
    set(project "cpkt_${name}_${variant}_project")
    set(source "${root}/src")
    set(source_root "${source}")
    if(recipe_SOURCE_SUBDIR)
      string(APPEND source_root "/${recipe_SOURCE_SUBDIR}")
    endif()
    set(extra "")
    if(recipe_OWNED_SOURCE)
      set(source_root "${CMAKE_SOURCE_DIR}/${recipe_OWNED_SOURCE}")
      list(APPEND extra "-DCPKT_UPSTREAM_SOURCE=${source}")
    endif()
    if(variant STREQUAL "static")
      list(APPEND extra -DBUILD_SHARED_LIBS=OFF)
    else()
      list(APPEND extra -DBUILD_SHARED_LIBS=ON)
    endif()
    string(REPLACE "<SOURCE_DIR>" "${source_root}" configured "${configure}")
    string(REPLACE "<BINARY_DIR>" "${root}/build-${variant}" configured "${configured}")
    if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      set(rpath "@loader_path")
    else()
      set(rpath "$ORIGIN")
    endif()
    if(CPKT_BUILD_DEPENDENCIES)
      file(MAKE_DIRECTORY "${prefix}/include" "${prefix}/lib")
      set(header_install "")
      foreach(header IN LISTS recipe_INSTALL_HEADERS)
        list(APPEND header_install COMMAND "${CMAKE_COMMAND}" -E copy_if_different
          "${source}/${header}" "${prefix}/include/")
      endforeach()
      set(download_extra "")
      set(byproducts "${prefix}/lib/lib${library}${CMAKE_STATIC_LIBRARY_SUFFIX}"
        "${prefix}/lib/lib${library}${CMAKE_SHARED_LIBRARY_SUFFIX}")
      if(variant STREQUAL "static")
        set(byproducts "${prefix}/lib/lib${library}${CMAKE_STATIC_LIBRARY_SUFFIX}")
      elseif(variant STREQUAL "shared")
        set(byproducts "${prefix}/lib/lib${library}${CMAKE_SHARED_LIBRARY_SUFFIX}")
      endif()
      if(variant STREQUAL "shared")
        # Both variants use the same extracted source; native dependencies order
        # static completion before configuring/installing the shared variant.
        list(APPEND prerequisites "cpkt_${name}_static_project")
        set(download_extra DOWNLOAD_COMMAND "" UPDATE_COMMAND "")
      endif()
      cpkt_cached_external_project_add(${project}
        URL "${url}" URL_HASH "${hash}"
        PREFIX "${root}/project-${variant}" SOURCE_DIR "${source}"
        BINARY_DIR "${root}/build-${variant}"
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE ${download_extra}
        DEPENDS ${prerequisites}
        CONFIGURE_COMMAND ${configured}
          "-DCMAKE_INSTALL_PREFIX=${prefix}" -DCMAKE_INSTALL_LIBDIR=lib
          "-DCMAKE_BUILD_TYPE=${CPKT_DEPENDENCY_BUILD_TYPE}"
          -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_TESTING=OFF
          "-DCMAKE_INSTALL_RPATH=${rpath}" -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
          ${common} ${extra} ${recipe_OPTIONS}
        BUILD_COMMAND ${build}
        INSTALL_COMMAND ${install} ${header_install} COMMAND ${strip}
        BUILD_BYPRODUCTS ${byproducts})
      cpkt_record_dependency_target(${project})
      list(APPEND projects "${project}")
    endif()
  endforeach()
  set_property(GLOBAL PROPERTY "CPKT_CODEC_PROJECTS_${name}" "${projects}")
  cpkt_codec_import("${name}" "${library}")
  set(CPKT_${name}_PREFIX "${prefix}" PARENT_SCOPE)
endfunction()

function(cpkt_codec_autotools name url hash library)
  set(root "${CPKT_DEPENDENCY_BUILD_ROOT}/${name}")
  set(prefix "${CPKT_EXTERNAL_ROOT}/${name}/install")
  set(project "cpkt_${name}_project")
  cpkt_component_producer_prerequisites(prerequisites "${name}")
  cpkt_append_pinned_external_toolchain_env_args(environment)
  cpkt_get_external_c_flags(flags)
  cpkt_get_strip_dependency_install_command(strip "${prefix}")
  execute_process(COMMAND "${CMAKE_C_COMPILER}" -dumpmachine
    OUTPUT_VARIABLE host OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
  find_program(make NAMES gmake make REQUIRED)
  if(CPKT_BUILD_DEPENDENCIES)
    file(MAKE_DIRECTORY "${prefix}/include" "${prefix}/lib")
    cpkt_cached_external_project_add(${project}
      URL "${url}" URL_HASH "${hash}" DOWNLOAD_EXTRACT_TIMESTAMP TRUE
      PREFIX "${root}/project" SOURCE_DIR "${root}/src" BINARY_DIR "${root}/build"
      DEPENDS ${prerequisites}
      CONFIGURE_COMMAND "${CMAKE_COMMAND}" -E env ${environment} "CFLAGS=${flags}"
        "${root}/src/configure" "--host=${host}" "--prefix=${prefix}"
        "--libdir=${prefix}/lib" --enable-static --enable-shared --with-pic ${ARGN}
      BUILD_COMMAND "${CMAKE_COMMAND}" -E env ${environment} "${make}" "-j${CPKT_DEPENDENCY_BUILD_JOBS}"
      INSTALL_COMMAND "${CMAKE_COMMAND}" -E env ${environment} "${make}" install
        COMMAND ${strip}
      BUILD_BYPRODUCTS "${prefix}/lib/lib${library}${CMAKE_STATIC_LIBRARY_SUFFIX}"
        "${prefix}/lib/lib${library}${CMAKE_SHARED_LIBRARY_SUFFIX}")
    cpkt_record_dependency_target(${project})
    set_property(GLOBAL PROPERTY "CPKT_CODEC_PROJECTS_${name}" "${project}")
  endif()
  cpkt_codec_import("${name}" "${library}")
  set(CPKT_${name}_PREFIX "${prefix}" PARENT_SCOPE)
endfunction()
