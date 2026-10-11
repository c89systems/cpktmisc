function(cpkt_add_xz)
  cpkt_codec_cmake(xz
    "https://github.com/tukaani-project/xz/releases/download/v${CPKT_XZ_VERSION}/xz-${CPKT_XZ_VERSION}.tar.gz"
    "SHA256=0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9" lzma DUAL
    OPTIONS -DXZ_NLS=OFF -DXZ_TOOL_XZ=OFF -DXZ_TOOL_XZDEC=OFF
      -DXZ_TOOL_LZMADEC=OFF -DXZ_TOOL_LZMAINFO=OFF -DXZ_TOOL_SCRIPTS=OFF -DXZ_DOC=OFF)
  foreach(kind static shared)
    set_property(TARGET cpkt::xz_${kind} PROPERTY INTERFACE_LINK_LIBRARIES Threads::Threads)
  endforeach()
  set(CPKT_xz_PREFIX "${CPKT_xz_PREFIX}" PARENT_SCOPE)
endfunction()
