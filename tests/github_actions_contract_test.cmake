cmake_minimum_required(VERSION 3.21)
if(NOT CPKT_REPO)
  get_filename_component(CPKT_REPO "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()
file(READ "${CPKT_REPO}/.github/workflows/darwin-bundle.yml" workflow)
foreach(required "workflow_dispatch:" "contents: read" "persist-credentials: false" "ref: \${{ github.sha }}"
    "make test-darwin-native" "test \"$(git rev-parse HEAD)\" = \"\${GITHUB_SHA}\""
    "build/package-stage/arm64-apple-darwin/misc/archives/*.tar.gz"
    "if: always()" "pkg-config llvm" "llvm_bin=\"$(brew --prefix llvm)/bin\""
    "printf '%s\\n' \"$llvm_bin\" >> \"$GITHUB_PATH\"")
  string(FIND "${workflow}" "${required}" found)
  if(found LESS 0)
    message(FATAL_ERROR "Missing native workflow requirement: ${required}")
  endif()
endforeach()
if(NOT workflow MATCHES "\non:\n  workflow_dispatch:\n\npermissions:")
  message(FATAL_ERROR "Native macOS diagnostics must have only a manual workflow_dispatch trigger")
endif()
foreach(forbidden "contents: write" "secrets." "CPKT_HANDOFF" "gh release" "git push" "make release" "python3 tests/")
  string(FIND "${workflow}" "${forbidden}" found)
  if(NOT found LESS 0)
    message(FATAL_ERROR "Unexpected workflow action: ${forbidden}")
  endif()
endforeach()
