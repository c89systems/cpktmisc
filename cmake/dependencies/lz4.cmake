function(cpkt_add_lz4)
  cpkt_codec_cmake(lz4
    "https://github.com/lz4/lz4/releases/download/v${CPKT_LZ4_VERSION}/lz4-${CPKT_LZ4_VERSION}.tar.gz"
    "SHA256=537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b" lz4
    SOURCE_SUBDIR build/cmake INSTALL_HEADERS lib/lz4frame_static.h
    OPTIONS -DBUILD_STATIC_LIBS=ON -DLZ4_BUILD_CLI=OFF
      -DLZ4_BUNDLED_MODE=OFF -DLZ4_POSITION_INDEPENDENT_LIB=ON)
  set(CPKT_lz4_PREFIX "${CPKT_lz4_PREFIX}" PARENT_SCOPE)
endfunction()
