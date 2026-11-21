add_library(ms_opt STATIC opt_bytetake.c opt_copyelim.c opt_copyelim_local.c opt_copyelim_move.c opt_copyelim_unbox.c opt_inline.c opt_inline_args.c opt_inline_closure.c opt_inline_dead.c opt_lastuse.c opt_lastuse_region.c opt_pipeline.c opt_simplify.c opt_simplify_cfg.c opt_simplify_fold.c opt_simplify_mutate.c opt_simplify_phis.c opt_simplify_probes.c opt_strfuse.c opt_util.c)
ms_target_defaults(ms_opt)
target_link_libraries(ms_opt PUBLIC ms_mir ms_base)
