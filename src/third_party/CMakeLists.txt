# Vendored libraries (see c-libs.lock). Built without the project warning set: the code is not ours.
find_package(Threads REQUIRED)
# macOS runners carry Homebrew copies of some of these libraries in /usr/local/include, which -isystem does not outrank; plain -I does.
if(APPLE)
  set(MS_THIRD_PARTY_SYSTEM "")
else()
  set(MS_THIRD_PARTY_SYSTEM SYSTEM)
endif()

# mimalloc builds with its own CMakeLists.txt and documented options: the static library only, no malloc override
# (the runtime binds it through ms_alloc_install), no tests. Windows links the UCRT, which its mingw detection only
# learns from MSYSTEM=UCRT64; without MI_MINGW_UCRT64 it attaches twice and prints a stray newline (#6208).
set(MI_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(MI_BUILD_OBJECT OFF CACHE BOOL "" FORCE)
set(MI_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(MI_OVERRIDE OFF CACHE BOOL "" FORCE)
if(WIN32)
  set(MI_EXTRA_CPPDEFS "MI_MINGW_UCRT64" CACHE STRING "" FORCE)
endif()
add_subdirectory(mimalloc EXCLUDE_FROM_ALL)
# The project builds with CMAKE_C_EXTENSIONS OFF; mimalloc needs GNU extensions (syscall, madvise).
set_target_properties(mimalloc-static PROPERTIES C_EXTENSIONS ON)
add_library(mimalloc ALIAS mimalloc-static)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_link_libraries(mimalloc-static PUBLIC rt)
endif()

# llhttp builds with its own CMakeLists.txt: the static library only. Its configure step writes libllhttp.pc into
# the source tree; that file is ignored by git.
set(LLHTTP_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLHTTP_BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
add_subdirectory(llhttp EXCLUDE_FROM_ALL)
set_target_properties(llhttp_static PROPERTIES SYSTEM ON)
add_library(llhttp ALIAS llhttp_static)

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
target_include_directories(pcre2 ${MS_THIRD_PARTY_SYSTEM} PUBLIC ${PCRE2_GEN} PRIVATE ${PCRE2_DIR})
target_compile_definitions(pcre2 PUBLIC PCRE2_CODE_UNIT_WIDTH=8 PCRE2_STATIC
  PRIVATE HAVE_CONFIG_H SUPPORT_PCRE2_8 SUPPORT_UNICODE)


# zlib builds with its own CMakeLists.txt: the static library only, no examples, no install.
set(ZLIB_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZLIB_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(ZLIB_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(zlib EXCLUDE_FROM_ALL)
# Its headers are system headers for the runtime, as before: the project warning set stops at them.
set_target_properties(zlibstatic PROPERTIES SYSTEM ON)
add_library(zlib ALIAS zlibstatic)
# libuv builds with its own CMakeLists.txt: the static library only, no tests, no clang-tidy.
set(LIBUV_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ENABLE_CLANG_TIDY OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
add_subdirectory(libuv EXCLUDE_FROM_ALL)
set_target_properties(uv_a PROPERTIES SYSTEM ON)
add_library(uv ALIAS uv_a)
include(cmake/nghttp2.cmake)
include(cmake/openssl.cmake)
include(cmake/curl.cmake)
# The vendored files must match the lock (offline).
add_test(NAME third_party_lock
  COMMAND ${CMAKE_COMMAND} -DSOURCE_DIR=${CMAKE_SOURCE_DIR} -DMODE=verify -P ${CMAKE_SOURCE_DIR}/cmake/FetchCLibs.cmake)
