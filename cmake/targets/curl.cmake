# curl 8.23.0 (libcurl only), static, built with curl's own CMakeLists.txt. HTTP and HTTP/2 (nghttp2) with zlib and a
# threaded resolver; TLS through the vendored OpenSSL on every platform (Windows trusts its system certificate store).
#
# curl's configure step compiles and links against OpenSSL, and OpenSSL builds with its own Configure at build time
# (cmake/targets/openssl.cmake), so curl is an ExternalProject ordered after it instead of an add_subdirectory. zlib and nghttp2
# are in-tree targets, so their archives and headers are handed over as arguments.
include(ExternalProject)
set(CURL_DIR ${MS_TP}/curl)
set(CURL_BUILD ${MS_TP_BIN}/curl_build)
set(CURL_LIB ${CURL_BUILD}/lib/libcurl${CMAKE_STATIC_LIBRARY_SUFFIX})

string(TOUPPER "${CMAKE_BUILD_TYPE}" CURL_CONFIG)
set(CURL_C_FLAGS "${CMAKE_C_FLAGS}")
# OpenSSL builds out of tree, so its generated headers (opensslv.h, configuration.h) sit beside, not inside, the source include directory.
string(APPEND CURL_C_FLAGS " -isystem ${OPENSSL_BUILD}/include")
# zlib and nghttp2 do the same: zconf.h and nghttp2ver.h are generated into their build directories.
string(APPEND CURL_C_FLAGS " -isystem ${MS_TP_BIN}/zlib -isystem ${MS_TP_BIN}/nghttp2/lib/includes")
# nghttp2 is a static archive: without this its headers declare every symbol dllimport on Windows.
string(APPEND CURL_C_FLAGS " -DNGHTTP2_STATICLIB")
set(CURL_ARGS
  -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
  -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
  -DCMAKE_C_FLAGS=${CURL_C_FLAGS}
  -DCMAKE_C_FLAGS_${CURL_CONFIG}=${CMAKE_C_FLAGS_${CURL_CONFIG}}
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_DEBUG_POSTFIX=
  -DBUILD_CURL_EXE=OFF -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF
  -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF -DENABLE_CURL_MANUAL=OFF
  -DCURL_DISABLE_INSTALL=ON -DCURL_ENABLE_EXPORT_TARGET=OFF -DCMAKE_DISABLE_FIND_PACKAGE_Perl=ON
  -DCURL_USE_OPENSSL=ON -DCURL_USE_SCHANNEL=OFF -DOPENSSL_USE_STATIC_LIBS=ON
  -DOPENSSL_INCLUDE_DIR=${OPENSSL_DIR}/include -DOPENSSL_SSL_LIBRARY=${OPENSSL_SSL}
  -DOPENSSL_CRYPTO_LIBRARY=${OPENSSL_CRYPTO}
  -DUSE_NGHTTP2=ON
  -DNGHTTP2_INCLUDE_DIR=${MS_TP}/nghttp2/lib/includes
  -DNGHTTP2_LIBRARY=$<TARGET_FILE:nghttp2_static>
  -DCURL_ZLIB=ON -DZLIB_INCLUDE_DIR=${MS_TP}/zlib -DZLIB_LIBRARY=$<TARGET_FILE:zlibstatic>
  -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DENABLE_ARES=OFF -DUSE_LIBIDN2=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF
  -DENABLE_UNIX_SOCKETS=ON
  -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_FTP=ON -DCURL_DISABLE_GOPHER=ON
  -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON -DCURL_DISABLE_MQTT=ON
  -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_SMTP=ON -DCURL_DISABLE_TELNET=ON
  -DCURL_DISABLE_TFTP=ON)
if(APPLE)
  list(APPEND CURL_ARGS -DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}
    -DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET} -DCMAKE_OSX_SYSROOT=${CMAKE_OSX_SYSROOT})
endif()
if(MS_CCACHE)
  list(APPEND CURL_ARGS -DCMAKE_C_COMPILER_LAUNCHER=${MS_CCACHE})
endif()
ExternalProject_Add(curl_build
  PREFIX ${MS_TP_BIN}/curl_build-prefix
  SOURCE_DIR ${CURL_DIR}
  BINARY_DIR ${CURL_BUILD}
  DEPENDS openssl_build zlibstatic nghttp2_static
  CMAKE_ARGS ${CURL_ARGS}
  BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target libcurl_static
  INSTALL_COMMAND ""
  BUILD_BYPRODUCTS ${CURL_LIB}
  USES_TERMINAL_BUILD OFF)

add_library(curl STATIC IMPORTED GLOBAL)
set_target_properties(curl PROPERTIES IMPORTED_LOCATION ${CURL_LIB}
  INTERFACE_INCLUDE_DIRECTORIES ${CURL_DIR}/include INTERFACE_COMPILE_DEFINITIONS CURL_STATICLIB)
add_dependencies(curl curl_build)
target_link_libraries(curl INTERFACE zlib nghttp2 openssl_ssl)
if(WIN32)
  target_link_libraries(curl INTERFACE ws2_32 advapi32 crypt32 bcrypt iphlpapi)
else()
  target_link_libraries(curl INTERFACE Threads::Threads)
endif()
