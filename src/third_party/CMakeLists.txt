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

add_library(llhttp STATIC llhttp/src/api.c llhttp/src/http.c llhttp/src/llhttp.c)
target_include_directories(llhttp SYSTEM PUBLIC llhttp/include)

# PCRE2 builds with its own CMakeLists.txt: the 8-bit static library with Unicode properties and no JIT, no
# pcre2grep or tests. Consumers define the code unit width themselves, which the target also exports.
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(PCRE2_BUILD_PCRE2_8 ON CACHE BOOL "" FORCE)
set(PCRE2_BUILD_PCRE2GREP OFF CACHE BOOL "" FORCE)
set(PCRE2_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(PCRE2_SHOW_REPORT OFF CACHE BOOL "" FORCE)
set(PCRE2_SUPPORT_JIT OFF CACHE BOOL "" FORCE)
set(PCRE2_SUPPORT_UNICODE ON CACHE BOOL "" FORCE)
add_subdirectory(pcre2 EXCLUDE_FROM_ALL)
target_compile_definitions(pcre2-8-static PUBLIC PCRE2_CODE_UNIT_WIDTH=8)
set_target_properties(pcre2-8-static PROPERTIES SYSTEM ON)
add_library(pcre2 ALIAS pcre2-8-static)


# zlib builds with its own CMakeLists.txt: the static library only, no examples, no install.
set(ZLIB_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZLIB_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(ZLIB_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(zlib EXCLUDE_FROM_ALL)
# Its headers are system headers for the runtime, as before: the project warning set stops at them.
set_target_properties(zlibstatic PROPERTIES SYSTEM ON)
add_library(zlib ALIAS zlibstatic)
include(cmake/libuv.cmake)
include(cmake/nghttp2.cmake)
include(cmake/openssl.cmake)
include(cmake/curl.cmake)
# The vendored files must match the lock (offline).
add_test(NAME third_party_lock
  COMMAND ${CMAKE_COMMAND} -DSOURCE_DIR=${CMAKE_SOURCE_DIR} -DMODE=verify -P ${CMAKE_SOURCE_DIR}/cmake/FetchCLibs.cmake)
