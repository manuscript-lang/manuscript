add_library(ms_tooling STATIC lint_rules.c lint.c lint_text.c lint_effects.c lint_imports.c lint_unreachable.c lint_matches.c lint_calls.c lint_promises.c lint_recursion.c lint_terse.c lint_terse_stmts.c inspect.c diagram.c)
ms_target_defaults(ms_tooling)
target_include_directories(ms_tooling PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_link_libraries(ms_tooling PUBLIC ms_base ms_syntax ms_check)
