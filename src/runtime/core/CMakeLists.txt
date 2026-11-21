add_library(ms_core STATIC context.c stack.c)
ms_target_defaults(ms_core)
target_link_libraries(ms_core PUBLIC ms_sys ms_base)
