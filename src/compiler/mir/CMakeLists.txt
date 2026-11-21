add_library(ms_mir STATIC mir_builder.c mir_module.c mir_types.c)
ms_target_defaults(ms_mir)
target_link_libraries(ms_mir PUBLIC ms_base)
