# libuv 1.53.0, static. Source lists follow upstream's CMakeLists.txt for each platform.
set(UV_SRC ${CMAKE_CURRENT_SOURCE_DIR}/libuv/src)
add_library(uv STATIC
  ${UV_SRC}/fs-poll.c ${UV_SRC}/idna.c ${UV_SRC}/inet.c ${UV_SRC}/random.c ${UV_SRC}/strscpy.c
  ${UV_SRC}/strtok.c ${UV_SRC}/thread-common.c ${UV_SRC}/threadpool.c ${UV_SRC}/timer.c
  ${UV_SRC}/uv-common.c ${UV_SRC}/uv-data-getter-setters.c ${UV_SRC}/version.c)
target_include_directories(uv ${MS_THIRD_PARTY_SYSTEM} PUBLIC libuv/include)
target_include_directories(uv PRIVATE libuv/src)
if(WIN32)
  file(GLOB UV_WIN_SOURCES CONFIGURE_DEPENDS ${UV_SRC}/win/*.c)
  target_sources(uv PRIVATE ${UV_WIN_SOURCES})
  target_compile_definitions(uv PRIVATE WIN32_LEAN_AND_MEAN _WIN32_WINNT=0x0602 _CRT_DECLARE_NONSTDC_NAMES=0)
  target_link_libraries(uv PUBLIC ws2_32 advapi32 iphlpapi userenv shell32 ole32 dbghelp user32 psapi)
else()
  target_sources(uv PRIVATE
    ${UV_SRC}/unix/async.c ${UV_SRC}/unix/core.c ${UV_SRC}/unix/dl.c ${UV_SRC}/unix/fs.c
    ${UV_SRC}/unix/getaddrinfo.c ${UV_SRC}/unix/getnameinfo.c ${UV_SRC}/unix/loop-watcher.c
    ${UV_SRC}/unix/loop.c ${UV_SRC}/unix/pipe.c ${UV_SRC}/unix/poll.c ${UV_SRC}/unix/process.c
    ${UV_SRC}/unix/proctitle.c ${UV_SRC}/unix/random-devurandom.c ${UV_SRC}/unix/signal.c
    ${UV_SRC}/unix/stream.c ${UV_SRC}/unix/tcp.c ${UV_SRC}/unix/thread.c ${UV_SRC}/unix/tty.c
    ${UV_SRC}/unix/udp.c)
  target_compile_definitions(uv PRIVATE _FILE_OFFSET_BITS=64 _LARGEFILE_SOURCE)
  target_link_libraries(uv PUBLIC Threads::Threads)
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_sources(uv PRIVATE
      ${UV_SRC}/unix/linux.c ${UV_SRC}/unix/procfs-exepath.c ${UV_SRC}/unix/random-getrandom.c
      ${UV_SRC}/unix/random-sysctl-linux.c)
    target_compile_definitions(uv PRIVATE _GNU_SOURCE _POSIX_C_SOURCE=200112)
    target_link_libraries(uv PUBLIC dl rt)
  elseif(APPLE)
    target_sources(uv PRIVATE
      ${UV_SRC}/unix/bsd-ifaddrs.c ${UV_SRC}/unix/kqueue.c ${UV_SRC}/unix/random-getentropy.c
      ${UV_SRC}/unix/darwin-proctitle.c ${UV_SRC}/unix/darwin.c ${UV_SRC}/unix/fsevents.c)
    target_compile_definitions(uv PRIVATE _DARWIN_UNLIMITED_SELECT=1 _DARWIN_USE_64_BIT_INODE=1)
  endif()
endif()
