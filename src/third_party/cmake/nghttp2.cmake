# nghttp2 1.71.0, static (library only). The version header is generated at configure time.
set(NGHTTP2_DIR ${CMAKE_CURRENT_SOURCE_DIR}/nghttp2/lib)
set(NGHTTP2_GEN ${CMAKE_CURRENT_BINARY_DIR}/nghttp2_gen)
set(PACKAGE_VERSION "1.71.0")
set(PACKAGE_VERSION_NUM "0x014700")
configure_file(${NGHTTP2_DIR}/includes/nghttp2/nghttp2ver.h.in ${NGHTTP2_GEN}/nghttp2/nghttp2ver.h @ONLY)
set(NGHTTP2_NAMES
  pq map queue frame buf stream outbound_item session submit helper alpn hd hd_huffman hd_huffman_data
  version priority_spec option callbacks mem http rcbuf extpri ratelim time debug)
set(NGHTTP2_SOURCES ${NGHTTP2_DIR}/sfparse.c)
foreach(name IN LISTS NGHTTP2_NAMES)
  list(APPEND NGHTTP2_SOURCES ${NGHTTP2_DIR}/nghttp2_${name}.c)
endforeach()
add_library(nghttp2 STATIC ${NGHTTP2_SOURCES})
target_include_directories(nghttp2 PUBLIC ${NGHTTP2_DIR}/includes ${NGHTTP2_GEN} PRIVATE ${NGHTTP2_DIR})
target_compile_definitions(nghttp2 PUBLIC NGHTTP2_STATICLIB PRIVATE BUILDING_NGHTTP2)
if(NOT WIN32)
  target_compile_definitions(nghttp2 PRIVATE HAVE_ARPA_INET_H=1 HAVE_NETINET_IN_H=1 HAVE_UNISTD_H=1)
endif()
