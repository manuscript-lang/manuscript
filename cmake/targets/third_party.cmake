# Vendored libraries (see src/third_party/c-libs.lock). Built without the project warning set: the code is not ours.
set(MS_TP ${CMAKE_SOURCE_DIR}/src/third_party)
set(MS_TP_BIN ${CMAKE_BINARY_DIR}/src/third_party)
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
add_subdirectory(${MS_TP}/mimalloc EXCLUDE_FROM_ALL)
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
add_subdirectory(${MS_TP}/llhttp EXCLUDE_FROM_ALL)
set_target_properties(llhttp_static PROPERTIES SYSTEM ON)
add_library(llhttp ALIAS llhttp_static)

# PCRE2 builds with its own CMakeLists.txt: the 8-bit static library with Unicode properties and no JIT, no
# pcre2grep or tests. Consumers define the code unit width themselves, which the target also exports.
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(PCRE2_BUILD_PCRE2_8 ON CACHE BOOL "" FORCE)
set(PCRE2_BUILD_PCRE2GREP OFF CACHE BOOL "" FORCE)
set(PCRE2_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(PCRE2_SHOW_REPORT OFF CACHE BOOL "" FORCE)
set(PCRE2_SUPPORT_JIT OFF CACHE BOOL "" FORCE)
set(PCRE2_SUPPORT_UNICODE ON CACHE BOOL "" FORCE)
add_subdirectory(${MS_TP}/pcre2 EXCLUDE_FROM_ALL)
target_compile_definitions(pcre2-8-static PUBLIC PCRE2_CODE_UNIT_WIDTH=8)
set_target_properties(pcre2-8-static PROPERTIES SYSTEM ON)
add_library(pcre2 ALIAS pcre2-8-static)


# zlib builds with its own CMakeLists.txt: the static library only, no examples, no install.
set(ZLIB_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZLIB_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(ZLIB_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(${MS_TP}/zlib EXCLUDE_FROM_ALL)
# Its headers are system headers for the runtime, as before: the project warning set stops at them.
set_target_properties(zlibstatic PROPERTIES SYSTEM ON)
add_library(zlib ALIAS zlibstatic)
# libuv builds with its own CMakeLists.txt: the static library only, no tests, no clang-tidy.
set(LIBUV_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ENABLE_CLANG_TIDY OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
add_subdirectory(${MS_TP}/libuv EXCLUDE_FROM_ALL)
set_target_properties(uv_a PROPERTIES SYSTEM ON)
add_library(uv ALIAS uv_a)
# nghttp2: its own CMakeLists, library only (no apps, examples, docs or tests), static.
set(ENABLE_LIB_ONLY ON CACHE BOOL "" FORCE)
set(ENABLE_DOC OFF CACHE BOOL "" FORCE)
set(ENABLE_FAILMALLOC OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
add_subdirectory(${MS_TP}/nghttp2 EXCLUDE_FROM_ALL)
set_target_properties(nghttp2_static PROPERTIES SYSTEM ON)
include(${CMAKE_SOURCE_DIR}/cmake/targets/openssl.cmake)
include(${CMAKE_SOURCE_DIR}/cmake/targets/curl.cmake)
# The vendored files must match the lock (offline).
add_test(NAME third_party_lock
  COMMAND ${CMAKE_COMMAND} -DSOURCE_DIR=${CMAKE_SOURCE_DIR} -DMODE=verify -P ${CMAKE_SOURCE_DIR}/cmake/FetchCLibs.cmake)
