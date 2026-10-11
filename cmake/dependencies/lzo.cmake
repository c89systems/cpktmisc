function(cpkt_add_lzo)
  cpkt_codec_cmake(lzo
    "https://www.oberhumer.com/opensource/lzo/download/lzo-${CPKT_LZO_VERSION}.tar.gz"
    "SHA256=c0f892943208266f9b6543b3ae308fab6284c5c90e627931446fb49b4221a072" lzo2
    OPTIONS -DENABLE_STATIC=ON -DENABLE_SHARED=ON)
  set(CPKT_lzo_PREFIX "${CPKT_lzo_PREFIX}" PARENT_SCOPE)
endfunction()
