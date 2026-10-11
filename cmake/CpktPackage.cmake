# Staging is separate from explicit test commands and requires their actual proof.
# This control target is available in every selected graph. Its action scopes
# staging to CPKT_GROUP; the inventory owner "all" describes orchestration.
add_custom_target(package-bundle
  COMMAND bash "${CMAKE_SOURCE_DIR}/scripts/package-stage.sh"
    --group "${CPKT_GROUP}" --preset "$ENV{CPKT_PRESET}"
  VERBATIM)

function(cpkt_bind_package_proof)
  if(TARGET cpkt_verify_runtime)
    add_dependencies(package-bundle cpkt_verify_runtime)
  endif()
endfunction()
cmake_language(DEFER CALL cpkt_bind_package_proof)
if(CPKT_TARGET_ID STREQUAL "arm64-apple-darwin" AND CMAKE_BUILD_TYPE STREQUAL "Release")
  add_custom_target(package-darwin-smoke
    COMMAND bash "${CMAKE_SOURCE_DIR}/scripts/darwin-smoke-package.sh" "${CPKT_BUNDLE_VERSION}"
    DEPENDS package-bundle cpkt_abi_smoke_static cpkt_abi_smoke_shared VERBATIM)
endif()
