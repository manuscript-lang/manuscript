add_library(ms_lower STATIC lower_types.c)
ms_target_defaults(ms_lower)
target_link_libraries(ms_lower PUBLIC ms_base ms_syntax ms_check ms_own ms_mir)
