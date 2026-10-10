include_guard(GLOBAL)
# Normalize built Autotools dylibs before libtool copies them into the owned
# install prefix. Facade links then import the relative upstream ABI identity.
function(cpkt_codec_darwin_build_identity project library_directory)
  if(NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR NOT CPKT_BUILD_DEPENDENCIES)
    return()
  endif()
  cpkt_append_pinned_external_toolchain_env_args(environment)
  ExternalProject_Add_Step(${project} darwin-identities
    COMMAND "${CMAKE_COMMAND}" -E env ${environment} "${CMAKE_COMMAND}"
      "-DCPKT_DARWIN_LIBRARY_DIR=${library_directory}"
      "-DCPKT_DARWIN_STAGE_LIBRARY_DIR=${library_directory}"
      "-DCPKT_DARWIN_INSTALL_NAME_TOOL=${CMAKE_INSTALL_NAME_TOOL}"
      "-DCPKT_DARWIN_OTOOL=${CPKT_OTOOL}"
      -P "${CMAKE_SOURCE_DIR}/cmake/normalize_darwin_dylib_install_names.cmake"
    DEPENDEES build DEPENDERS install
    DEPENDS "${CMAKE_SOURCE_DIR}/cmake/normalize_darwin_dylib_install_names.cmake")
endfunction()
