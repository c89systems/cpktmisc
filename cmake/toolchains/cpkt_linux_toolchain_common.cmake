# Linux configuration discovers prepared tools; it never provisions them.
include("${CMAKE_CURRENT_LIST_DIR}/../CpktToolchainDiscovery.cmake")
function(cpkt_configure_bootlin_toolchain target_id)
  cpkt_discover_bootlin_toolchain("${target_id}")
endfunction()
