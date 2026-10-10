function(cpkt_add_bzip2)
  cpkt_codec_cmake(bzip2
    "https://sourceware.org/pub/bzip2/bzip2-${CPKT_BZIP2_VERSION}.tar.gz"
    "SHA256=ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269" bz2
    OWNED_SOURCE cmake/upstream/bzip2)
  set(CPKT_bzip2_PREFIX "${CPKT_bzip2_PREFIX}" PARENT_SCOPE)
endfunction()
