# Vendored libraries (see c-libs.lock). Built without the project warning set: the code is not ours.
find_package(Threads REQUIRED)

add_library(mimalloc STATIC mimalloc/src/static.c)
target_include_directories(mimalloc PUBLIC mimalloc/include)
target_include_directories(mimalloc PRIVATE mimalloc/src)
target_compile_definitions(mimalloc PRIVATE MI_STATIC_LIB)
target_link_libraries(mimalloc PUBLIC Threads::Threads)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_link_libraries(mimalloc PUBLIC rt)
endif()

add_library(llhttp STATIC llhttp/src/api.c llhttp/src/http.c llhttp/src/llhttp.c)
target_include_directories(llhttp PUBLIC llhttp/include)

# The vendored files must match the lock (offline).
add_test(NAME third_party_lock
  COMMAND ${CMAKE_COMMAND} -DSOURCE_DIR=${CMAKE_SOURCE_DIR} -DMODE=verify -P ${CMAKE_SOURCE_DIR}/cmake/FetchCLibs.cmake)
