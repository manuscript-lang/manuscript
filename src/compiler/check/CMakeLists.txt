add_library(ms_check STATIC builtins.c check.c declare.c types.c type_ops.c)
ms_target_defaults(ms_check)
target_link_libraries(ms_check PUBLIC ms_base ms_syntax ms_project)
