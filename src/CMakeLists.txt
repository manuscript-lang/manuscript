add_subdirectory(third_party)
add_subdirectory(base)
add_subdirectory(abi)
add_subdirectory(runtime)
if(MS_LIBC STREQUAL "musl")
  return() # the inner build of the `--static` runtime holds the runtime archives only
endif()
add_subdirectory(compiler)
add_subdirectory(tooling)
add_subdirectory(driver)
add_subdirectory(lint)

# `cmake --build <dir> --target conform-c`: the one progress number (plan rule 4).
# MS_ORACLE_DIR holds the oracle `ms-conform` built from 660429d4, outside the repository.
set(MS_ORACLE_DIR "$ENV{MS_ORACLE_DIR}" CACHE PATH "Directory with the oracle ms and ms-conform")
set(MS_CONFORM_EXTRA "" CACHE STRING "Extra ms-conform selection, semicolon separated")
add_custom_target(conform-c
  COMMAND ${CMAKE_COMMAND}
    "-DMS_CONFORM=${MS_ORACLE_DIR}/ms-conform${CMAKE_EXECUTABLE_SUFFIX}"
    "-DMS_C=$<TARGET_FILE:ms-c>"
    "-DSOURCE_DIR=${CMAKE_SOURCE_DIR}"
    "-DEXTRA=${MS_CONFORM_EXTRA}"
    -P "${CMAKE_SOURCE_DIR}/cmake/ConformC.cmake"
  DEPENDS ms-c
  USES_TERMINAL
  COMMENT "Running the conformance corpus against ms-c")
