add_library(ms_tooling STATIC lint_rules.c)
ms_target_defaults(ms_tooling)
target_include_directories(ms_tooling PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_link_libraries(ms_tooling PUBLIC ms_base)
