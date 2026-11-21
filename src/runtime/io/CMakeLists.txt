# The reactor on libuv: one loop per scheduler thread, the completion ring, and the per-OS hooks.
if(WIN32)
  set(MS_IO_OS windows)
else()
  set(MS_IO_OS posix)
endif()
add_library(ms_io STATIC ring.c reactor.c refused.c stdout.c stop.c ${MS_IO_OS}/platform.c)
ms_target_defaults(ms_io)
target_link_libraries(ms_io PUBLIC ms_abi ms_base ms_sys uv)
