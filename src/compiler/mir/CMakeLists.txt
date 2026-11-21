add_library(ms_mir STATIC mir_data.c mir_data_const.c mir_desc.c mir_glue.c mir_glue_alt.c mir_glue_alt_clone.c mir_glue_build.c mir_glue_clone.c mir_glue_closure.c mir_glue_deep.c mir_glue_demand.c mir_glue_drop.c mir_glue_types.c mir_analysis.c mir_boxing.c mir_edit.c mir_builder.c mir_frames.c mir_layout.c mir_module.c mir_pass.c mir_shape.c mir_slot_scope.c mir_types.c)
ms_target_defaults(ms_mir)
target_link_libraries(ms_mir PUBLIC ms_base)
