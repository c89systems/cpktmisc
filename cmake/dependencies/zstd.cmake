function(cpkt_add_zstd)
  cpkt_codec_cmake(zstd
    "https://github.com/facebook/zstd/releases/download/v${CPKT_ZSTD_VERSION}/zstd-${CPKT_ZSTD_VERSION}.tar.gz"
    "SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3" zstd
    SOURCE_SUBDIR build/cmake OPTIONS
      -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_SHARED=ON -DZSTD_FRAMEWORK=OFF
      -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF -DZSTD_MULTITHREAD_SUPPORT=ON)
  set(CPKT_zstd_PREFIX "${CPKT_zstd_PREFIX}" PARENT_SCOPE)
endfunction()
