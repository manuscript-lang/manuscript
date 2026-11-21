# mimalloc: the runtime's allocator, built as one object from its static.c, no libc override.
set(MS_MIMALLOC_DIR "${CMAKE_SOURCE_DIR}/runtime/third_party/mimalloc")
add_library(ms_mimalloc STATIC "${MS_MIMALLOC_DIR}/src/static.c")
target_include_directories(ms_mimalloc PUBLIC "${MS_MIMALLOC_DIR}/include")
target_include_directories(ms_mimalloc PRIVATE "${MS_MIMALLOC_DIR}/src")
target_compile_options(ms_mimalloc PRIVATE -O2 -w ${MS_C_FLAGS})
target_compile_definitions(ms_mimalloc PRIVATE MI_SECURE=0 MI_DEBUG=0 NDEBUG)
if(NOT MS_WINDOWS)
  # glibc before 2.34 keeps pthread_setspecific in libpthread, which a program using the allocator must name.
  find_package(Threads REQUIRED)
  target_link_libraries(ms_mimalloc PUBLIC Threads::Threads)
endif()
