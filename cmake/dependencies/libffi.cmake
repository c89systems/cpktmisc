include("${CMAKE_CURRENT_LIST_DIR}/darwin-codec-identities.cmake")
function(cpkt_add_libffi)
  set(platform_options "")
  if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    cpkt_get_external_c_flags(assembly_flags)
    string(REPLACE "-include stdint.h -include sys/types.h" "" assembly_flags "${assembly_flags}")
    # Preprocessed assembly must not inherit the SDK's C-only forced includes.
    list(APPEND platform_options "CCASFLAGS=${assembly_flags}")
  endif()
  cpkt_codec_autotools(libffi
    "https://github.com/libffi/libffi/releases/download/v${CPKT_LIBFFI_VERSION}/libffi-${CPKT_LIBFFI_VERSION}.tar.gz"
    "SHA256=7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4" ffi
    --disable-docs --disable-multi-os-directory ${platform_options})
  cpkt_codec_darwin_build_identity(cpkt_libffi_project "${CPKT_DEPENDENCY_BUILD_ROOT}/libffi/build/.libs")
  set(CPKT_libffi_PREFIX "${CPKT_libffi_PREFIX}" PARENT_SCOPE)
endfunction()
