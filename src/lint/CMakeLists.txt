add_executable(ms_lint main.c rules.c layers.c repo.c text.c)
ms_target_defaults(ms_lint)

# `cmake --build <dir> --target lint`: lists the repository's files, then runs ms_lint.
add_custom_target(lint
  COMMAND ${CMAKE_COMMAND}
    "-DMS_LINT=$<TARGET_FILE:ms_lint>"
    "-DSOURCE_DIR=${CMAKE_SOURCE_DIR}"
    "-DLIST_FILE=${CMAKE_BINARY_DIR}/lint-files.txt"
    -P "${CMAKE_SOURCE_DIR}/cmake/RunLint.cmake"
  DEPENDS ms_lint
  USES_TERMINAL
  COMMENT "Running ms_lint")
