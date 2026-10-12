cmake_minimum_required(VERSION 3.21)
include("${CPKT_ROOT}/tests/test-command.cmake")
set(work "${CPKT_SCRATCH}/independent-providers")
file(REMOVE_RECURSE "${work}")
set(core "${work}/core SDK")
set(misc "${work}/misc SDK")
file(MAKE_DIRECTORY "${core}/lib/cmake/CpktCore" "${misc}/lib/cmake/CpktMisc/pkg-config" "${work}/source")
# Archive tests exercise the real core guard. This small fixture supplies a
# versioned, independently validated SDK and CMake's native version selection.
set(core_config [=[function(cpkt_sdk_assert_targets group)
endfunction()
get_filename_component(CpktCore_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." REALPATH)
_cpkt_misc_validate_prefix("${CpktCore_PREFIX}" core)
file(READ "${CpktCore_PREFIX}/share/cpkt/packages/core.json" supplied)
string(JSON CpktCore_VERSION GET "${supplied}" release_version)
string(JSON CpktCore_TARGET_ID GET "${supplied}" target_id)
string(JSON CpktCore_PACKAGE_ID GET "${supplied}" package_id)
set(CpktCore_COMPATIBLE_SINCE "@FLOOR@")
]=])
include(CMakePackageConfigHelpers)
file(WRITE "${misc}/lib/libmisc_probe.a" "unchanged provider archive\n")
file(SHA256 "${misc}/lib/libmisc_probe.a" original_archive)
file(MAKE_DIRECTORY "${core}/lib/pkgconfig" "${misc}/lib/pkgconfig")
foreach(module cpkt-misc-probe cpkt-opcua cpkt-audio cpkt-sus)
  file(WRITE "${misc}/lib/pkgconfig/${module}.pc"
    "Name: ${module}\nDescription: Fixture misc\nVersion: 0.0.0\nRequires: cpkt-core >= 0.3.0\nLibs: -lmisc\n")
endforeach()
file(COPY_FILE "${CPKT_ROOT}/cmake/CpktMiscConfig.cmake" "${misc}/lib/cmake/CpktMisc/CpktMiscConfig.cmake")
file(COPY_FILE "${CPKT_ROOT}/cmake/CpktMiscValidate.cmake" "${misc}/lib/cmake/CpktMisc/Validate.cmake")
file(COPY_FILE "${CPKT_ROOT}/cmake/pkg-config-validation.cmake" "${misc}/lib/cmake/CpktMisc/pkg-config/CMakeLists.txt")

function(manifest prefix group version target requirement)
  file(GLOB_RECURSE paths LIST_DIRECTORIES FALSE RELATIVE "${prefix}" "${prefix}/lib/*")
  set(files "")
  set(separator "")
  foreach(path IN LISTS paths)
    file(CHMOD "${prefix}/${path}" PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ)
    file(SHA256 "${prefix}/${path}" hash)
    string(APPEND files "${separator}{\"mode\":\"0644\",\"path\":\"${path}\",\"sha256\":\"${hash}\",\"type\":\"file\"}")
    set(separator ,)
  endforeach()
  set(provenance "")
  if(group STREQUAL "misc")
    set(provenance "\"core_build_pin\":${build_pin},")
  endif()
  set(before "{\"components\":[],${provenance}\"files\":[${files}],\"group\":\"${group}\",\"libc\":\"gnu\",\"macos_deployment_target\":null,")
  set(after "\"release_version\":\"${version}\",\"requires_core\":${requirement},\"schema_version\":1,\"target_id\":\"${target}\"}")
  string(SHA256 id "${before}${after}")
  file(MAKE_DIRECTORY "${prefix}/share/cpkt/packages")
  file(WRITE "${prefix}/share/cpkt/packages/${group}.json" "${before}\"package_id\":\"${id}\",${after}")
  set(identity "{\"package_id\":\"${id}\",\"release_version\":\"${version}\",\"target_id\":\"${target}\"}" PARENT_SCOPE)
endfunction()
function(core_sdk version floor target)
  write_basic_package_version_file("${core}/lib/cmake/CpktCore/CpktCoreConfigVersion.cmake"
    VERSION "${version}" COMPATIBILITY AnyNewerVersion ARCH_INDEPENDENT)
  file(READ "${core}/lib/cmake/CpktCore/CpktCoreConfigVersion.cmake" native)
  file(WRITE "${core}/lib/cmake/CpktCore/CpktCoreConfigVersion.cmake"
    "if(NOT \"\${PACKAGE_FIND_VERSION}\" STREQUAL \"\" AND PACKAGE_FIND_VERSION VERSION_LESS \"${floor}\")\n"
    "  set(PACKAGE_VERSION \"${version}\")\n  set(PACKAGE_VERSION_COMPATIBLE FALSE)\n"
    "  set(PACKAGE_VERSION_EXACT FALSE)\n  return()\nendif()\n${native}")
  string(REPLACE "@FLOOR@" "${floor}" config "${core_config}")
  file(WRITE "${core}/lib/cmake/CpktCore/CpktCoreConfig.cmake" "${config}")
  file(WRITE "${core}/lib/pkgconfig/cpkt-core.pc"
    "prefix=\${pcfiledir}/../..\nName: cpkt-core\nDescription: Fixture core\nVersion: ${version}\nLibs: -lcore\n")
  manifest("${core}" core "${version}" "${target}" null)
  set(identity "${identity}" PARENT_SCOPE)
endfunction()
core_sdk(0.3.0 0.2.0 x86_64-linux-gnu)
set(build_pin "${identity}")
set(required "{\"release_version\":\"0.3.0\",\"target_id\":\"x86_64-linux-gnu\"}")
manifest("${misc}" misc 0.0.0 x86_64-linux-gnu "${required}")
file(SHA256 "${misc}/share/cpkt/packages/misc.json" original_manifest)
file(WRITE "${work}/source/CMakeLists.txt" [=[cmake_minimum_required(VERSION 3.21)
project(independent_providers NONE)
set(CMAKE_FIND_USE_CMAKE_ENVIRONMENT_PATH OFF)
set(CMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH OFF)
set(CMAKE_FIND_USE_CMAKE_SYSTEM_PATH OFF)
set(CMAKE_FIND_USE_PACKAGE_REGISTRY OFF)
set(CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY OFF)
list(PREPEND CMAKE_PREFIX_PATH "${MISC_ROOT}" "${CORE_ROOT}")
include("${MISC_ROOT}/lib/cmake/CpktMisc/Validate.cmake")
if(CORE_REQUEST)
  if(CORE_EXACT)
    find_package(CpktCore ${CORE_REQUEST} EXACT CONFIG REQUIRED)
  else()
    find_package(CpktCore ${CORE_REQUEST} CONFIG REQUIRED)
  endif()
endif()
if(FOREIGN_LIBRARY)
  add_library(foreign STATIC IMPORTED)
  set_target_properties(foreign PROPERTIES IMPORTED_LOCATION "${FOREIGN_LIBRARY}")
endif()
find_package(CpktMisc CONFIG REQUIRED)
cpkt_misc_assert_targets()
]=])
function(configure name)
  cpkt_test_command("${CMAKE_COMMAND}" -G Ninja -S "${work}/source" -B "${work}/${name}"
    "-DMISC_ROOT=${misc}" "-DCORE_ROOT=${core}" ${ARGN})
endfunction()
function(reject name)
  cpkt_test_failure("CpktCore|core prerequisite mismatch|SDK architecture mismatch"
    "${CMAKE_COMMAND}" -G Ninja -S "${work}/source" -B "${work}/${name}"
    "-DMISC_ROOT=${misc}" "-DCORE_ROOT=${core}" ${ARGN})
endfunction()
find_program(pkg_config NAMES pkg-config REQUIRED)
function(check_pc name)
  cpkt_test_command("${CMAKE_COMMAND}" -E env
    "PKG_CONFIG_PATH=${misc}/lib/pkgconfig:${core}/lib/pkgconfig" "PKG_CONFIG_LIBDIR="
    "${CMAKE_COMMAND}" -S "${misc}/lib/cmake/CpktMisc/pkg-config" -B "${work}/pc-${name}"
    "-DCPKT_SDK_PREFIX=${misc}")
  cpkt_test_command("${CMAKE_COMMAND}" -E env
    "PKG_CONFIG_PATH=${misc}/lib/pkgconfig:${core}/lib/pkgconfig" "PKG_CONFIG_LIBDIR="
    "${pkg_config}" --static --libs cpkt-misc-probe)
endfunction()
configure(original)
check_pc(original)
core_sdk(0.2.0 0.2.0 x86_64-linux-gnu)
reject(old-core)
core_sdk(0.4.0 0.2.0 x86_64-linux-gnu)
configure(compatible-upgrade)
check_pc(upgrade)
configure(inclusive-range -DCORE_REQUEST=0.3.0...0.4.0)
reject(exclusive-range -DCORE_REQUEST=0.3.0...<0.4.0)
reject(exact-request -DCORE_REQUEST=0.3.0 -DCORE_EXACT=ON)
core_sdk(0.4.0 0.4.0 x86_64-linux-gnu)
reject(raised-floor)
# A version-only pkg-config query accepts this release; the CMake guard must reject it.
cpkt_test_command("${CMAKE_COMMAND}" -E env "PKG_CONFIG_PATH=${misc}/lib/pkgconfig:${core}/lib/pkgconfig"
  "PKG_CONFIG_LIBDIR=" "${pkg_config}" --static --libs cpkt-misc-probe)
cpkt_test_failure("CpktCore" "${CMAKE_COMMAND}" -E env
  "PKG_CONFIG_PATH=${misc}/lib/pkgconfig:${core}/lib/pkgconfig" "PKG_CONFIG_LIBDIR="
  "${CMAKE_COMMAND}" -S "${misc}/lib/cmake/CpktMisc/pkg-config"
  -B "${work}/pc-raised-floor" "-DCPKT_SDK_PREFIX=${misc}")
file(WRITE "${work}/compiler.sh" "#!/bin/sh\nprintf 'compiler invoked\\n' >> \"$CPKT_COMPILER_LOG\"\n")
file(CHMOD "${work}/compiler.sh" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
foreach(example audio-live-vox-c89 audio-sus-c89 audio-vox-intro-c89 opcua-c89 sus-live-vox-c89 sus-vox-intro-c89)
  cpkt_test_failure("CpktCore" "${CMAKE_COMMAND}" -E env "CPKT_SDK_PREFIX=${misc}"
    "PKG_CONFIG_PATH=${core}/lib/pkgconfig" "CC=${work}/compiler.sh" "CPKT_COMPILER_LOG=${work}/compiler.log"
    sh "${CPKT_ROOT}/examples/${example}/build-pkg-config.sh" "${work}/example-output")
endforeach()
if(EXISTS "${work}/compiler.log")
  message(FATAL_ERROR "pkg-config example compiled against a core with an incompatible floor")
endif()
core_sdk(0.4.0 0.2.0 aarch64-linux-gnu)
reject(wrong-target)
cpkt_test_failure("SDK target mismatch" "${CMAKE_COMMAND}" -E env
  "PKG_CONFIG_PATH=${misc}/lib/pkgconfig:${core}/lib/pkgconfig" "PKG_CONFIG_LIBDIR="
  "${CMAKE_COMMAND}" -S "${misc}/lib/cmake/CpktMisc/pkg-config"
  -B "${work}/pc-wrong-target" "-DCPKT_SDK_PREFIX=${misc}")
# Even a version file that accepts the baseline cannot replace the floor contract.
core_sdk(0.4.0 "" x86_64-linux-gnu)
cpkt_test_failure("compatibility baseline is outside" "${CMAKE_COMMAND}" -G Ninja
  -S "${work}/source" -B "${work}/missing-floor" "-DMISC_ROOT=${misc}" "-DCORE_ROOT=${core}")
cpkt_test_failure("compatibility baseline is outside" "${CMAKE_COMMAND}" -E env
  "PKG_CONFIG_PATH=${misc}/lib/pkgconfig:${core}/lib/pkgconfig" "PKG_CONFIG_LIBDIR="
  "${CMAKE_COMMAND}" -S "${misc}/lib/cmake/CpktMisc/pkg-config"
  -B "${work}/pc-missing-floor" "-DCPKT_SDK_PREFIX=${misc}")
core_sdk(0.4.0 0.2.0 x86_64-linux-gnu)
configure(different-package-id)
file(RELATIVE_PATH relative_misc "${CMAKE_CURRENT_BINARY_DIR}" "${misc}")
cpkt_test_command("${CMAKE_COMMAND}" -E env "CPKT_SDK_PREFIX=${relative_misc}"
  "PKG_CONFIG_PATH=${core}/lib/pkgconfig" "CC=${work}/compiler.sh" "CPKT_COMPILER_LOG=${work}/compiler.log"
  sh "${CPKT_ROOT}/examples/opcua-c89/build-pkg-config.sh" "${work}/example-output")
foreach(example audio-live-vox-c89 audio-sus-c89 audio-vox-intro-c89 opcua-c89 sus-live-vox-c89 sus-vox-intro-c89)
  cpkt_test_command("${CMAKE_COMMAND}" -E env "CPKT_SDK_PREFIX=${misc}"
    "PKG_CONFIG_PATH=${core}/lib/pkgconfig" "CC=${work}/compiler.sh" "CPKT_COMPILER_LOG=${work}/compiler.log"
    sh "${CPKT_ROOT}/examples/${example}/build-pkg-config.sh" "${work}/example-output")
endforeach()
file(STRINGS "${work}/compiler.log" compiler_calls)
list(LENGTH compiler_calls compiler_count)
if(NOT compiler_count EQUAL 7)
  message(FATAL_ERROR "Compatible pkg-config launchers did not reach their compilers")
endif()
set(other_core "${work}/other compatible core")
file(COPY "${core}/" DESTINATION "${other_core}")
core_sdk(0.4.0 0.4.0 x86_64-linux-gnu)
cpkt_test_failure("CpktCore|different core SDK" "${CMAKE_COMMAND}" -E env "CPKT_SDK_PREFIX=${misc}"
  "CMAKE_PREFIX_PATH=${other_core}" "PKG_CONFIG_PATH=" "PKG_CONFIG_LIBDIR=${core}/lib/pkgconfig"
  "CC=${work}/compiler.sh" "CPKT_COMPILER_LOG=${work}/compiler.log"
  sh "${CPKT_ROOT}/examples/opcua-c89/build-pkg-config.sh" "${work}/example-output")
core_sdk(0.4.0 0.2.0 x86_64-linux-gnu)
set(selected_core "${core}")
set(core "${other_core}")
core_sdk(0.4.0 0.4.0 x86_64-linux-gnu)
set(core "${selected_core}")
cpkt_test_command("${CMAKE_COMMAND}" -E env "CPKT_SDK_PREFIX=${misc}"
  "CMAKE_PREFIX_PATH=${other_core}" "PKG_CONFIG_PATH=" "PKG_CONFIG_LIBDIR=${core}/lib/pkgconfig"
  "CC=${work}/compiler.sh" "CPKT_COMPILER_LOG=${work}/compiler.log"
  sh "${CPKT_ROOT}/examples/opcua-c89/build-pkg-config.sh" "${work}/example-output")
file(STRINGS "${work}/compiler.log" compiler_calls)
list(LENGTH compiler_calls compiler_count)
if(NOT compiler_count EQUAL 8)
  message(FATAL_ERROR "Compatible pkg-config selection did not reach its compiler")
endif()
file(SHA256 "${misc}/lib/libmisc_probe.a" archive_after)
file(SHA256 "${misc}/share/cpkt/packages/misc.json" manifest_after)
if(NOT archive_after STREQUAL original_archive OR NOT manifest_after STREQUAL original_manifest)
  message(FATAL_ERROR "Core upgrades changed provider archives or provenance")
endif()
cpkt_test_failure("CpktCore" "${CMAKE_COMMAND}" -G Ninja -S "${work}/source" -B "${work}/missing"
  "-DMISC_ROOT=${misc}")
cpkt_test_failure("cpkt-core" "${CMAKE_COMMAND}" -E env "PKG_CONFIG_PATH=${misc}/lib/pkgconfig"
  "PKG_CONFIG_LIBDIR=" "${pkg_config}" --libs cpkt-misc-probe)
file(MAKE_DIRECTORY "${work}/foreign")
file(WRITE "${work}/foreign/libmisc_probe.a" "foreign library\n")
cpkt_test_failure("Existing target foreign imports SDK library" "${CMAKE_COMMAND}" -G Ninja
  -S "${work}/source" -B "${work}/foreign-target" "-DMISC_ROOT=${misc}" "-DCORE_ROOT=${core}"
  "-DFOREIGN_LIBRARY=${work}/foreign/libmisc_probe.a")
file(RENAME "${misc}" "${work}/relocated misc")
set(misc "${work}/relocated misc")
cpkt_test_command("${CMAKE_COMMAND}" -E env "CPKT_SDK_PREFIX=${misc}"
  "PKG_CONFIG_PATH=${core}/lib/pkgconfig" "CC=${work}/compiler.sh" "CPKT_COMPILER_LOG=${work}/compiler.log"
  sh "${CPKT_ROOT}/examples/opcua-c89/build-pkg-config.sh" "${work}/example-output")
configure(relocated-misc)
check_pc(relocated-misc)
file(RENAME "${core}" "${work}/relocated core")
set(core "${work}/relocated core")
configure(relocated-core)
check_pc(relocated-core)
file(APPEND "${core}/lib/pkgconfig/cpkt-core.pc" "# tampered\n")
cpkt_test_failure("SDK payload differs" "${CMAKE_COMMAND}" -G Ninja
  -S "${work}/source" -B "${work}/corrupt-core" "-DMISC_ROOT=${misc}" "-DCORE_ROOT=${core}")
file(APPEND "${misc}/lib/cmake/CpktMisc/Validate.cmake" "# corrupted\n")
cpkt_test_failure("SDK payload differs" "${CMAKE_COMMAND}" -G Ninja
  -S "${work}/source" -B "${work}/corrupt" "-DMISC_ROOT=${misc}" "-DCORE_ROOT=${core}")
