add_library(ms_check STATIC constants.c symbol_text.c effects_directives.c effects_paths.c effects_reach.c builtins.c check.c declare.c imports.c resolve.c types.c type_ops.c)
ms_target_defaults(ms_check)
target_link_libraries(ms_check PUBLIC ms_base ms_syntax ms_project)
