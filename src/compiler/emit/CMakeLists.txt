set(EMIT_SOURCES emit_leaf.c emit_memory.c emit_scalar.c)
add_library(ms_emit STATIC ${EMIT_SOURCES})
ms_target_defaults(ms_emit)
target_link_libraries(ms_emit PUBLIC ms_mir ms_base)
