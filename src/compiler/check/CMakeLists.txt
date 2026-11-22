add_library(ms_check STATIC import_errors.c import_fix.c suggest.c scope_walk.c names.c names_hint.c names_habit.c std_exports.c mutate.c mutate_fix.c fallthrough.c effects_scan.c returns.c fallthrough_type.c constants.c symbol_text.c effects_directives.c effects_paths.c effects_reach.c builtins.c check.c declare.c imports.c resolve.c signatures.c methods.c implements.c properties.c bounds.c instantiate.c typevars.c types.c type_ops.c)
ms_target_defaults(ms_check)
target_link_libraries(ms_check PUBLIC ms_base ms_syntax ms_project)
# Body checking (the Checker owner's files).
target_sources(ms_check PRIVATE facts.c bodies.c exprs.c exprs_ops.c conversions.c calls.c match.c mismatch.c native.c)
target_sources(ms_check PRIVATE drop_labels.c)
target_sources(ms_check PRIVATE exprs_mismatch.c)
