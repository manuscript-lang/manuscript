add_library(ms_lower STATIC lower_types.c lower_scope.c lower_func.c lower_expr.c lower_stmt.c lower_call.c lower_native.c lower_conv.c lower_for.c lower_text.c lower_match.c lower_list.c lower_iflet.c)
ms_target_defaults(ms_lower)
target_link_libraries(ms_lower PUBLIC ms_base ms_syntax ms_check ms_own ms_mir)
