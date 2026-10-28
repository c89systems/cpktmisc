function(cpkt_add_libarchive)
  # Function availability checks must link: compile-only probes incorrectly
  # claim Windows-only symbols exist when compiling the Linux/Apple sources.
  set(options -DCMAKE_TRY_COMPILE_TARGET_TYPE=EXECUTABLE
    -DENABLE_LZO=OFF -DENABLE_LZ4=ON -DENABLE_LZMA=ON
    -DENABLE_ZSTD=ON -DENABLE_ZLIB=ON -DENABLE_BZip2=ON
    -DENABLE_OPENSSL=ON -DENABLE_LIBXML2=ON -DENABLE_EXPAT=OFF
    -DENABLE_NETTLE=OFF -DENABLE_MBEDTLS=OFF -DENABLE_LIBB2=OFF
    -DENABLE_PCREPOSIX=OFF -DENABLE_PCRE2POSIX=OFF -DENABLE_ACL=OFF
    -DENABLE_TEST=OFF -DENABLE_TAR=OFF -DENABLE_CPIO=OFF -DENABLE_CAT=OFF -DENABLE_UNZIP=OFF
    "-DZLIB_INCLUDE_DIR=${CPKT_CORE_PREFIX}/include"
    "-DOPENSSL_INCLUDE_DIR=${CPKT_CORE_PREFIX}/include"
    "-DLIBXML2_INCLUDE_DIR=${CPKT_CORE_PREFIX}/include/libxml2")
  foreach(pair "bzip2|BZIP2|bz2" "xz|LIBLZMA|lzma" "lz4|LZ4|lz4" "zstd|ZSTD|zstd")
    string(REPLACE "|" ";" fields "${pair}")
    list(GET fields 0 name)
    list(GET fields 1 variable)
    list(GET fields 2 library)
    list(APPEND options "-D${variable}_INCLUDE_DIR=${CPKT_EXTERNAL_ROOT}/${name}/install/include"
      "-D${variable}_LIBRARY=${CPKT_EXTERNAL_ROOT}/${name}/install/lib/lib${library}${CMAKE_SHARED_LIBRARY_SUFFIX}")
  endforeach()
  foreach(pair "ZLIB|z" "OPENSSL_SSL|ssl" "OPENSSL_CRYPTO|crypto" "LIBXML2|xml2")
    string(REPLACE "|" ";" fields "${pair}")
    list(GET fields 0 variable)
    list(GET fields 1 library)
    list(APPEND options "-D${variable}_LIBRARY=${CPKT_CORE_PREFIX}/lib/lib${library}${CMAKE_SHARED_LIBRARY_SUFFIX}")
  endforeach()
  # FindBZip2 uses the configuration-specific cache entry, not BZIP2_LIBRARY.
  list(APPEND options
    "-DBZIP2_LIBRARY_RELEASE=${CPKT_EXTERNAL_ROOT}/bzip2/install/lib/libbz2${CMAKE_SHARED_LIBRARY_SUFFIX}")
  cpkt_codec_cmake(libarchive
    "https://github.com/libarchive/libarchive/releases/download/v${CPKT_LIBARCHIVE_VERSION}/libarchive-${CPKT_LIBARCHIVE_VERSION}.tar.gz"
    "SHA256=f5a6539059cf5e597dbeda37bfa4874b1e8dea063c8d93bf85a2b44af90a5bd4" archive
    OPTIONS ${options})
  foreach(kind static shared)
    set_property(TARGET cpkt::libarchive_${kind} PROPERTY INTERFACE_LINK_LIBRARIES
      "cpkt::bzip2_${kind};cpkt::xz_${kind};cpkt::lz4_${kind};cpkt::zstd_${kind};cpkt::zlib_${kind};cpkt::openssl_ssl_${kind};cpkt::openssl_crypto_${kind};cpkt::libxml2_${kind};Threads::Threads")
  endforeach()
  set(CPKT_libarchive_PREFIX "${CPKT_libarchive_PREFIX}" PARENT_SCOPE)
endfunction()
