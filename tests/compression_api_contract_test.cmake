include("${CPKT_SOURCE}/cmake/CpktMutationPaths.cmake")
set(work "${CPKT_BINARY}/api-contract")
cpkt_validate_mutation_paths("${work}/source/CMakeLists.txt" "${work}/build/CMakeCache.txt"
  "${work}/native/ffi.h" "${work}/generated/ffi/include/cpkt/ffi.h")
file(MAKE_DIRECTORY "${work}/source" "${work}/native" "${work}/generated/ffi/include/cpkt")
file(WRITE "${work}/native/ffi.h" [=[
#define FFI_VALUE 9
typedef enum { FFI_OK, FFI_ERROR } ffi_status;
typedef struct { int value; struct { int nested; } detail; } ffi_type;
extern ffi_type ffi_public;
int ffi_operation(int value);
]=])
set(header [=[
#ifdef __cplusplus
extern "C" {
#endif
#define CPKT_FFI_FFI_VALUE 9
enum { CPKT_FFI_FFI_OK, CPKT_FFI_FFI_ERROR };
typedef unsigned int cpkt_ffi_ffi_status;
typedef struct { int value; struct { int nested; } detail; } cpkt_ffi_ffi_type;
cpkt_ffi_ffi_type *cpkt_ffi_ffi_public_ref(void);
int cpkt_ffi_ffi_operation(int value);
#ifdef __cplusplus
}
#endif
]=])
file(WRITE "${work}/generated/ffi/coverage.json" [=[
{"functions":{"ffi_operation":{}},"variables":{"ffi_public":{}},"types":["ffi_status","ffi_type"]}
]=])
file(WRITE "${work}/source/library.c" [=[
static int record;
void *cpkt_ffi_ffi_public_ref(void) { return &record; }
#ifndef OMIT_OPERATION
int cpkt_ffi_ffi_operation(int value) { return value; }
#endif
]=])
file(WRITE "${work}/source/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.21)
project(api_contract C)
add_library(facade_static STATIC library.c)
add_library(facade_shared SHARED library.c)
add_library(incomplete_shared SHARED library.c)
target_compile_definitions(incomplete_shared PRIVATE OMIT_OPERATION)
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/libraries.cmake" CONTENT
  "set(static \"$<TARGET_FILE:facade_static>\")\nset(shared \"$<TARGET_FILE:facade_shared>\")\nset(incomplete \"$<TARGET_FILE:incomplete_shared>\")\nset(nm \"${CMAKE_NM}\")\n")
]=])
find_program(clang clang REQUIRED)
execute_process(COMMAND "${CMAKE_COMMAND}" -S "${work}/source" -B "${work}/build"
  "-DCMAKE_C_COMPILER=${clang}"
  COMMAND_ERROR_IS_FATAL ANY OUTPUT_QUIET)
execute_process(COMMAND "${CMAKE_COMMAND}" --build "${work}/build" --parallel 1
  COMMAND_ERROR_IS_FATAL ANY OUTPUT_QUIET)
include("${work}/build/libraries.cmake")
foreach(case complete macro enum type field nested_field function variable export static_export)
  set(candidate "${header}")
  set(library "${shared}")
  set(static_library "${static}")
  set(expected "")
  if(case STREQUAL "macro")
    string(REPLACE "#define CPKT_FFI_FFI_VALUE 9" "" candidate "${candidate}")
    set(expected "Missing public macro FFI_VALUE")
  elseif(case STREQUAL "enum")
    string(REPLACE "CPKT_FFI_FFI_ERROR }" "CPKT_FFI_FFI_ERROR = 7 }" candidate "${candidate}")
    set(expected "cpkt_enum_probe_FFI_ERROR")
  elseif(case STREQUAL "type")
    string(REPLACE "typedef unsigned int cpkt_ffi_ffi_status;" "" candidate "${candidate}")
    set(expected "cpkt_ffi_ffi_status")
  elseif(case STREQUAL "field" OR case STREQUAL "nested_field")
    if(case STREQUAL "field")
      set(field value)
    else()
      set(field nested)
    endif()
    string(REPLACE "int ${field};" "int removed_${field};" candidate "${candidate}")
    set(expected "no member named '${field}'")
  elseif(case STREQUAL "function")
    string(REPLACE "int cpkt_ffi_ffi_operation(int value);" "" candidate "${candidate}")
    set(expected "cpkt_ffi_ffi_operation")
  elseif(case STREQUAL "variable")
    string(REPLACE "cpkt_ffi_ffi_type *cpkt_ffi_ffi_public_ref(void);" "" candidate "${candidate}")
    set(expected "cpkt_ffi_ffi_public_ref")
  elseif(case STREQUAL "export")
    set(library "${incomplete}")
    set(expected "Missing ffi SHARED public binding: cpkt_ffi_ffi_operation")
  elseif(case STREQUAL "static_export")
    set(static_library "${incomplete}")
    set(expected "Missing ffi STATIC public binding: cpkt_ffi_ffi_operation")
  endif()
  file(WRITE "${work}/generated/ffi/include/cpkt/ffi.h" "${candidate}")
  execute_process(COMMAND "${CMAKE_COMMAND}" "-DCPKT_SOURCE=${CPKT_SOURCE}" "-DCPKT_BINARY=${work}"
    -DCPKT_LIBRARY=ffi "-DCPKT_CLANG=${clang}" "-DCPKT_NATIVE_INCLUDE=${work}/native"
    "-DCPKT_REPORT=${work}/generated/ffi/coverage.json" "-DCPKT_SYSTEM=${CMAKE_HOST_SYSTEM_NAME}"
    "-DCPKT_NM=${nm}" "-DCPKT_STATIC=${static_library}" "-DCPKT_SHARED=${library}"
    -P "${CPKT_SOURCE}/tests/compression_api_test.cmake"
    RESULT_VARIABLE status OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(case STREQUAL "complete")
    if(NOT status EQUAL 0)
      message(FATAL_ERROR "Valid API fixture rejected: ${out}${err}")
    endif()
  elseif(status EQUAL 0 OR NOT "${out}${err}" MATCHES "${expected}")
    message(FATAL_ERROR "Incomplete API ${case} was not rejected correctly: ${out}${err}")
  endif()
endforeach()
