set(EMIT_SOURCES emit_leaf.c emit_memory.c emit_scalar.c emit_call.c emit_checked.c emit_record.c emit_term.c emit_func.c emit.c emit_decl.c emit_entry.c)
add_library(ms_emit STATIC ${EMIT_SOURCES})
ms_target_defaults(ms_emit)
target_link_libraries(ms_emit PUBLIC ms_mir ms_base)
