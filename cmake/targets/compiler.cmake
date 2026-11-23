ms_library(ms_mir compiler/mir
  SOURCES
    mir_pipeline.c mir_verify.c mir_verify_own.c mir_verify_types.c mir_verify_types_core.c mir_verify_types_data.c
    mir_verify_types_ops.c mir_count_ops.c mir_depth.c mir_cancel_edges.c mir_shed.c mir_unwind.c mir_unwind_closers.c
    mir_unwind_flow.c mir_unwind_hash.c mir_unwind_loops.c mir_unwind_own.c mir_unwind_slots.c mir_unwind_cells.c
    mir_unwind_walk.c mir_elab.c mir_elab_state.c mir_elab_tags.c mir_elab_emit.c mir_elab_edge.c mir_elab_block.c
    mir_elab_close.c mir_hash.c mir_persist.c mir_print.c mir_print_func.c mir_print_ty.c mir_lower_ops.c
    mir_lower_ops_blocks.c mir_expand.c mir_expand_owned.c mir_tables.c mir_data.c mir_desc_glue.c mir_json_tree.c
    mir_data_const.c mir_desc.c mir_glue.c mir_glue_alt.c mir_glue_alt_clone.c mir_glue_build.c mir_glue_clone.c
    mir_glue_closure.c mir_glue_deep.c mir_glue_demand.c mir_glue_drop.c mir_glue_types.c mir_analysis.c
    mir_boxing.c mir_edit.c mir_builder.c mir_frames.c mir_layout.c mir_module.c mir_pass.c mir_shape.c
    mir_shape_table.c mir_slot_scope.c mir_types.c
  LINK ms_base)

# The runtime natives' parameter lists, generated from the ms-sig comments of src/runtime. The table is read by
# lowering and by the ownership pass (which natives borrow their result).
set(native_sigs ${MS_GEN}/native_sigs.c)
file(GLOB_RECURSE runtime_headers CONFIGURE_DEPENDS ${CMAKE_SOURCE_DIR}/src/runtime/*.h)
add_custom_command(
  OUTPUT ${native_sigs}
  COMMAND ${CMAKE_COMMAND} -DSRC_DIR=${CMAKE_SOURCE_DIR}/src/runtime -DOUTPUT=${native_sigs}
          -P ${CMAKE_SOURCE_DIR}/cmake/EmbedNativeSigs.cmake
  DEPENDS ${runtime_headers} ${CMAKE_SOURCE_DIR}/cmake/EmbedNativeSigs.cmake
  COMMENT "Generating native signatures")
ms_library(ms_native_sigs compiler/natives
  SOURCES
    native_sig.c ${native_sigs}
  LINK ms_base)

ms_library(ms_syntax compiler/syntax
  SOURCES
    diag_codes.c diag_json.c format.c format_compact.c format_cuts.c format_group.c format_import.c format_layout.c
    format_render.c format_spacing.c format_syntax.c format_text.c format_tree.c lex.c lex_continue.c lex_layout.c
    lex_scan.c lex_text.c lex_token.c lex_unicode.c parse.c parse_bind.c parse_core.c parse_decl.c parse_decl_item.c
    parse_expr.c parse_primary.c parse_stmt.c parse_tables.c parse_text.c parse_type.c partial.c partial_lines.c
    partial_recover.c token.c walk.c
  LINK ms_base)

# The bundled standard library is generated from stdlib/ at build time.
set(std_embedded ${MS_GEN}/std_embedded.c)
file(GLOB_RECURSE std_files CONFIGURE_DEPENDS ${CMAKE_SOURCE_DIR}/stdlib/*.ms)
add_custom_command(
  OUTPUT ${std_embedded}
  COMMAND ${CMAKE_COMMAND} -DSTDLIB_DIR=${CMAKE_SOURCE_DIR}/stdlib -DOUTPUT=${std_embedded}
          -P ${CMAKE_SOURCE_DIR}/cmake/EmbedStdlib.cmake
  DEPENDS ${std_files} ${CMAKE_SOURCE_DIR}/cmake/EmbedStdlib.cmake
  COMMENT "Embedding stdlib/*.ms")
ms_library(ms_project compiler/project
  SOURCES
    discover.c edit.c embed.c files.c lock.c load.c manifest.c manifest_packages.c project.c package.c resolve.c
    attach.c attach_effects.c semver.c solve.c solve_choose.c toml.c workspace.c ${std_embedded}
  LINK ms_syntax ms_base)

ms_library(ms_emit compiler/emit
  SOURCES
    emit_leaf.c emit_memory.c emit_scalar.c emit_call.c emit_checked.c emit_record.c emit_term.c emit_func.c emit.c
    emit_decl.c emit_entry.c emit_data.c emit_option.c emit_list.c emit_string.c emit_closure.c emit_iface.c
    emit_task.c emit_debug.c emit_tables.c emit_hints.c emit_copies.c emit_wide.c
  LINK ms_mir ms_base)

# One linker per OS family.
if(WIN32)
  set(link_os link_windows.c)
elseif(APPLE)
  set(link_os link_macos.c macho.c sdk_stubs.c)
else()
  set(link_os link_linux.c glibc_stubs.c glibc_table.c)
endif()
ms_library(ms_link compiler/link
  SOURCES
    link.c link_job.c object.c llvm_inproc.c asm_scan.c asm_tables.c ${link_os}
  LINK ms_emit ms_base)

ms_library(ms_check compiler/check
  SOURCES
    import_errors.c import_fix.c suggest.c scope_walk.c names.c names_hint.c names_habit.c std_exports.c mutate.c
    mutate_fix.c fallthrough.c message_fixes.c shadow.c effects_scan.c dispatch_targets.c lazy_std.c std_cache.c returns.c fallthrough_type.c constants.c
    exports.c symbol_text.c effects_directives.c effects_paths.c effects_reach.c builtins.c check.c declare.c
    imports.c resolve.c signatures.c methods.c implements.c properties.c bounds.c instantiate.c typevars.c types.c
    type_ops.c facts.c bodies.c exprs.c exprs_ops.c conversions.c calls.c call_target.c call_report.c match.c
    mismatch.c native.c operands.c members.c drop_labels.c test_fixture.c recursion.c order.c exprs_mismatch.c
    try_check.c opaque.c externs.c
  LINK ms_base ms_syntax ms_project)

ms_library(ms_own compiler/own
  SOURCES
    class.c own.c unused.c changes.c borrows.c uses.c escapes.c moves.c closers.c taken.c result_borrows.c bind.c
    live_expr.c live_set.c live_stmt.c places.c overlaps.c relays.c expr_text.c
  LINK ms_base ms_syntax ms_project ms_check ms_native_sigs)

ms_library(ms_opt compiler/opt
  SOURCES
    opt_appendfast.c opt_bytesfast.c opt_bytetake.c opt_copyelim.c opt_copyelim_local.c opt_copyelim_move.c
    opt_copyelim_unbox.c opt_exit_drops.c opt_ifconv.c opt_inline.c opt_inline_args.c opt_inline_closure.c
    opt_fieldview.c opt_inline_dead.c opt_lastuse.c opt_lastuse_region.c opt_loopslot.c opt_optparam.c opt_pipeline.c opt_probe.c
    opt_range.c opt_range_eval.c opt_range_len.c opt_range_prove.c opt_range_refine.c opt_reserve.c opt_simplify.c
    opt_simplify_cfg.c opt_simplify_fold.c opt_simplify_mutate.c opt_simplify_phis.c opt_simplify_probes.c
    opt_sortgen.c opt_sortgen_drift.c opt_sortgen_emit.c opt_sortgen_merge.c opt_strfast.c opt_strfuse.c opt_util.c
    opt_viewfast.c
  LINK ms_mir ms_base m)

ms_library(ms_lower compiler/lower
  SOURCES
    lower_types.c lower_scope.c lower_func.c lower_expr.c lower_stmt.c lower_destructure.c lower_field.c lower_call.c lower_var_slot.c lower_native.c
    lower_native_list.c lower_native_roles.c lower_scalar_ops.c lower_object.c lower_extern.c lower_conv.c lower_for.c lower_close.c lower_parts.c
    lower_temp.c lower_text.c lower_match.c lower_list.c lower_iflet.c lower_closure.c lower_captures.c
    lower_funcval.c lower_default.c lower_glue.c lower_hooks.c lower_result.c lower_tests.c lower_entry.c
  LINK ms_base ms_syntax ms_check ms_own ms_mir ms_native_sigs)
