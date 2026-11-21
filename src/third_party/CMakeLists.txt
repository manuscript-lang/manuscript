# Vendored libraries (see c-libs.lock). Built without the project warning set: the code is not ours.
find_package(Threads REQUIRED)

add_library(mimalloc STATIC mimalloc/src/static.c)
target_include_directories(mimalloc SYSTEM PUBLIC mimalloc/include)
target_include_directories(mimalloc PRIVATE mimalloc/src)
target_compile_definitions(mimalloc PRIVATE MI_STATIC_LIB)
target_link_libraries(mimalloc PUBLIC Threads::Threads)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_link_libraries(mimalloc PUBLIC rt)
endif()

add_library(llhttp STATIC llhttp/src/api.c llhttp/src/http.c llhttp/src/llhttp.c)
target_include_directories(llhttp SYSTEM PUBLIC llhttp/include)

# PCRE2, 8-bit with Unicode properties and no JIT. The generic headers and tables are copied at configure
# time, so nothing in the vendored tree is edited.
set(PCRE2_DIR ${CMAKE_CURRENT_SOURCE_DIR}/pcre2/src)
set(PCRE2_GEN ${CMAKE_CURRENT_BINARY_DIR}/pcre2_gen)
configure_file(${PCRE2_DIR}/pcre2.h.generic ${PCRE2_GEN}/pcre2.h COPYONLY)
configure_file(${PCRE2_DIR}/config.h.generic ${PCRE2_GEN}/config.h COPYONLY)
configure_file(${PCRE2_DIR}/pcre2_chartables.c.dist ${PCRE2_GEN}/pcre2_chartables.c COPYONLY)
add_library(pcre2 STATIC
  ${PCRE2_GEN}/pcre2_chartables.c
  ${PCRE2_DIR}/pcre2_auto_possess.c ${PCRE2_DIR}/pcre2_chkdint.c ${PCRE2_DIR}/pcre2_compile.c
  ${PCRE2_DIR}/pcre2_compile_cgroup.c ${PCRE2_DIR}/pcre2_compile_class.c ${PCRE2_DIR}/pcre2_config.c
  ${PCRE2_DIR}/pcre2_context.c ${PCRE2_DIR}/pcre2_convert.c ${PCRE2_DIR}/pcre2_dfa_match.c
  ${PCRE2_DIR}/pcre2_error.c ${PCRE2_DIR}/pcre2_extuni.c ${PCRE2_DIR}/pcre2_find_bracket.c
  ${PCRE2_DIR}/pcre2_jit_compile.c ${PCRE2_DIR}/pcre2_maketables.c ${PCRE2_DIR}/pcre2_match.c
  ${PCRE2_DIR}/pcre2_match_data.c ${PCRE2_DIR}/pcre2_match_next.c ${PCRE2_DIR}/pcre2_newline.c
  ${PCRE2_DIR}/pcre2_ord2utf.c ${PCRE2_DIR}/pcre2_pattern_info.c ${PCRE2_DIR}/pcre2_script_run.c
  ${PCRE2_DIR}/pcre2_serialize.c ${PCRE2_DIR}/pcre2_string_utils.c ${PCRE2_DIR}/pcre2_study.c
  ${PCRE2_DIR}/pcre2_substitute.c ${PCRE2_DIR}/pcre2_substring.c ${PCRE2_DIR}/pcre2_tables.c
  ${PCRE2_DIR}/pcre2_ucd.c ${PCRE2_DIR}/pcre2_valid_utf.c ${PCRE2_DIR}/pcre2_xclass.c)
target_include_directories(pcre2 SYSTEM PUBLIC ${PCRE2_GEN} PRIVATE ${PCRE2_DIR})
target_compile_definitions(pcre2 PUBLIC PCRE2_CODE_UNIT_WIDTH=8 PCRE2_STATIC
  PRIVATE HAVE_CONFIG_H SUPPORT_PCRE2_8 SUPPORT_UNICODE)


include(cmake/zlib.cmake)
include(cmake/libuv.cmake)
include(cmake/nghttp2.cmake)
include(cmake/openssl.cmake)
include(cmake/curl.cmake)
# The vendored files must match the lock (offline).
add_test(NAME third_party_lock
  COMMAND ${CMAKE_COMMAND} -DSOURCE_DIR=${CMAKE_SOURCE_DIR} -DMODE=verify -P ${CMAKE_SOURCE_DIR}/cmake/FetchCLibs.cmake)
