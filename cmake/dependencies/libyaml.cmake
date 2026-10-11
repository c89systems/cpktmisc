include("${CMAKE_CURRENT_LIST_DIR}/darwin-codec-identities.cmake")
function(cpkt_add_libyaml)
  set(platform_options "")
  if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    execute_process(COMMAND "${CMAKE_C_COMPILER}" -dumpmachine
      OUTPUT_VARIABLE host OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    string(REGEX REPLACE "^arm64-" "aarch64-" host "${host}")
    # Autoconf's final --host option is authoritative. The 0.2.5 config.sub
    # recognizes the GNU spelling, while osxcross reports the Apple spelling.
    list(APPEND platform_options "--host=${host}")
  endif()
  cpkt_codec_autotools(libyaml
    "https://github.com/yaml/libyaml/releases/download/${CPKT_LIBYAML_VERSION}/yaml-${CPKT_LIBYAML_VERSION}.tar.gz"
    "SHA256=c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4" yaml ${platform_options})
  cpkt_codec_darwin_build_identity(cpkt_libyaml_project "${CPKT_DEPENDENCY_BUILD_ROOT}/libyaml/build/src/.libs")
  set(CPKT_libyaml_PREFIX "${CPKT_libyaml_PREFIX}" PARENT_SCOPE)
endfunction()
