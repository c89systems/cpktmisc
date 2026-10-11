# Source generation follows the selected target's preprocessor and system headers.
find_program(CPKT_CODEC_CLANG clang REQUIRED)
find_program(CPKT_CODEC_PYTHON python3 REQUIRED)
if(NOT CPKT_SOURCE)
  set(CPKT_SOURCE "${CMAKE_SOURCE_DIR}")
endif()
set(codec_arguments)
if(CMAKE_C_COMPILER_ID MATCHES "Clang")
  set(codec_clang "${CMAKE_C_COMPILER}")
else()
  set(codec_clang "${CPKT_CODEC_CLANG}")
  if(CMAKE_SYSROOT)
    execute_process(COMMAND "${CMAKE_C_COMPILER}" -dumpmachine
      OUTPUT_VARIABLE codec_triple OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    list(APPEND codec_arguments "--clang-argument=--target=${codec_triple}"
      "--clang-argument=--sysroot=${CMAKE_SYSROOT}")
  endif()
endif()
foreach(library ffi archive zstd lzma lz4 lzo)
  set(native "${library}")
  if(library STREQUAL "ffi")
    set(native libffi)
  elseif(library STREQUAL "archive")
    set(native libarchive)
  elseif(library STREQUAL "lzma")
    set(native xz)
  endif()
  set(generated "${CMAKE_BINARY_DIR}/generated/${library}")
  string(TOUPPER "${library}" upper)
  set(CPKT_${upper}_GENERATED "${generated}")
  file(GLOB_RECURSE headers CONFIGURE_DEPENDS "${CPKT_EXTERNAL_ROOT}/${native}/install/include/*.h")
  set(outputs "${generated}/include/cpkt/${library}.h" "${generated}/src/${library}.c"
    "${generated}/exports.txt" "${generated}/coverage.json"
    "${generated}/exports.map" "${generated}/exports.darwin"
    "${generated}/native_layout.c" "${generated}/public_layout.c")
  if(COMMAND cpkt_register_generated_outputs)
    cpkt_register_generated_outputs(${outputs})
  endif()
  set(adapters)
  if(library STREQUAL "archive" OR library STREQUAL "lzma")
    list(APPEND adapters "${CPKT_SOURCE}/src/${library}_adapter.inc")
  endif()
  set(arguments ${codec_arguments})
  if(library STREQUAL "archive")
    # Upstream's large-file probes select this ABI on 32-bit glibc. The
    # facade must use the same stat layout, including full-width st_size.
    list(APPEND arguments "--clang-argument=-D_FILE_OFFSET_BITS=64")
  endif()
  set(CPKT_${upper}_CLANG_ARGUMENTS "${arguments}")
  set(CPKT_CODEC_GENERATOR_CLANG "${codec_clang}")
  add_custom_command(OUTPUT ${outputs}
    COMMAND "${CPKT_CODEC_PYTHON}" "${CPKT_SOURCE}/tools/generate_compression_facade.py"
      --library "${library}" --include "${CPKT_EXTERNAL_ROOT}/${native}/install/include"
      --output "${generated}" --clang "${codec_clang}" ${arguments}
    COMMAND "${CMAKE_COMMAND}" "-DCPKT_CATALOG=${generated}/exports.txt"
      "-DCPKT_OUTPUT=${generated}" -P "${CPKT_SOURCE}/cmake/generate_facade_exports.cmake"
    DEPENDS "${CPKT_SOURCE}/tools/generate_compression_facade.py"
      "${CPKT_SOURCE}/scripts/generated_output_paths.py"
      "${CPKT_SOURCE}/cmake/generate_facade_exports.cmake" ${headers} ${adapters}
    VERBATIM)
  add_custom_target(cpkt_${library}_sources DEPENDS ${outputs})
endforeach()
