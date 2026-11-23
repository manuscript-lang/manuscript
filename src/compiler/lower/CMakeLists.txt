add_library(ms_lower STATIC lower_types.c lower_scope.c lower_func.c lower_expr.c lower_stmt.c lower_place.c lower_call.c lower_native.c lower_native_list.c lower_object.c lower_extern.c lower_conv.c lower_for.c lower_close.c lower_parts.c lower_temp.c lower_text.c lower_match.c lower_list.c lower_iflet.c lower_closure.c lower_captures.c lower_funcval.c lower_default.c lower_glue.c lower_hooks.c lower_result.c lower_tests.c lower_entry.c)
ms_target_defaults(ms_lower)
target_link_libraries(ms_lower PUBLIC ms_base ms_syntax ms_check ms_own ms_mir ms_native_sigs)
