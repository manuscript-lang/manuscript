add_library(ms_check STATIC facts.c import_errors.c import_fix.c suggest.c mutate.c mutate_fix.c fallthrough.c fallthrough_type.c constants.c symbol_text.c effects_directives.c effects_paths.c effects_reach.c builtins.c check.c declare.c imports.c resolve.c signatures.c methods.c implements.c properties.c typevars.c types.c type_ops.c)
ms_target_defaults(ms_check)
target_link_libraries(ms_check PUBLIC ms_base ms_syntax ms_project)
