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

# `cmake --build <dir> --target conform`: the conformance corpus (parse, check, run, test) and the command
# fixtures, replayed against the ms built here, one `passed/total` line each (cmake/Conform.cmake).
# MS_CONFORM_ENFORCE=ON fails the target on any corpus difference; the command fixtures always must pass.
option(MS_CONFORM_ENFORCE "Fail conform when a corpus phase has a difference" OFF)
add_custom_target(conform
  COMMAND ${CMAKE_COMMAND} "-DMS=$<TARGET_FILE:ms-c>" "-DSOURCE_DIR=${CMAKE_SOURCE_DIR}"
    "-DENFORCE=${MS_CONFORM_ENFORCE}" -P "${CMAKE_SOURCE_DIR}/cmake/Conform.cmake"
  DEPENDS ms-c
  USES_TERMINAL
  COMMENT "Replaying the conformance corpus and the command fixtures")

# The command fixtures alone (tests/conformance/commands).
add_custom_target(conform-commands
  COMMAND ${CMAKE_COMMAND} "-DMS=$<TARGET_FILE:ms-c>" "-DSOURCE_DIR=${CMAKE_SOURCE_DIR}" -DONLY=commands
    -P "${CMAKE_SOURCE_DIR}/cmake/Conform.cmake"
  DEPENDS ms-c
  USES_TERMINAL
  COMMENT "Replaying the command fixtures")
