/* Owns writing one function: its header, entry block, instructions. */
#include "compiler/emit/emit_func.h"

#include "base/alloc.h"
#include "base/fatal.h"
#include "compiler/emit/emit.h"
#include "compiler/emit/emit_debug.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

/* A checked operation on a sized integer also faults when its result leaves the type's range. */
/* MS_POISON_SLOTS: a volatile fill of 0xDD over each shared cell whose occupant `index` of `block` reads last. */
static void emit_poison_fills(EmitCx *cx, uint32_t block, uint32_t index) {
  for (uint32_t at = 0; at < cx->npoison; at++) {
    const EmitPoison *fill = &cx->poison[at];
    if (fill->block == block && fill->index == index) {
      ms_strbuild_printf(cx->out, "  call void @llvm.memset.p0.i64(ptr %%cell%u, i8 -35, i64 %u, i1 true)\n", fill->cell,
                         fill->bytes);
    }
  }
}

static bool emit_instruction(EmitCx *cx, const MirInst *inst, const EmitSite *site) {
  bool handled = false;
  bool ok = emit_scalar_op(cx, inst, site, &handled);
  if (!handled) {
    ok = emit_checked_op(cx, inst, site, &handled);
  }
  if (!handled) {
    ok = emit_memory_inst(cx, inst, site, &handled);
  }
  if (!handled) {
    ok = emit_closure_op(cx, inst, site, &handled);
  }
  if (!handled) {
    ok = emit_iface_op(cx, inst, site, &handled);
  }
  if (!handled) {
    ok = emit_task_op(cx, inst, &handled);
  }
  if (!handled) {
    ok = emit_string_op(cx, inst, site, &handled);
  }
  if (!handled) {
    ok = emit_list_op(cx, inst, site, &handled);
  }
  if (!handled) {
    ok = emit_option_op(cx, inst, site, &handled);
  }
  if (!handled) {
    ok = emit_record_op(cx, inst, site, &handled);
  }
  if (!handled) {
    ok = emit_data_op(cx, inst, site, &handled);
  }
  if (!handled) {
    ok = emit_call_op(cx, inst, site, &handled);
  }
  if (!handled) {
    cx->why = mir_op_info[inst->op].name;
    return false;
  }
  if (!ok) {
    return false;
  }
  int64_t lo = 0;
  int64_t hi = 0;
  if (!mir_sized_result_range(cx->module, cx->func, inst, &lo, &hi)) {
    return true;
  }
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out,
                     "  %%l%ua = icmp slt i64 %%v%u, %lld\n  %%l%ub = icmp sgt i64 %%v%u, %lld\n"
                     "  %%l%us = or i1 %%l%ua, %%l%ub\n",
                     number, inst->res, (long long)lo, number, inst->res, (long long)hi, number, number, number);
  char bad[24];
  emit_text_name(bad, sizeof bad, "l", number, "s", MIR_NONE);
  emit_fault_if(cx, site, bad, "msrt_post_int_range", NULL, 0);
  return true;
}

/* Whether the function's boundary is one the emitter handles: layouts that did not fail, and an entry block
 * that nothing branches to (it cannot hold phis). */
static bool types_ok(EmitCx *cx) {
  const MirFunc *func = cx->func;
  for (uint32_t value = 0; value < func->values.len; value++) {
    (void)emit_leaves(cx, func->values.ptr[value]);
  }
  if (cx->layouts->failed) {
    cx->why = "type layout";
    return false;
  }
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirTerm *term = &func->blocks.ptr[block].term;
    for (uint32_t edge = 0; edge < emit_edge_count(term); edge++) {
      if (emit_edge(term, edge)->block == 0) {
        cx->why = "entry block is a branch target";
        return false;
      }
    }
  }
  return true;
}

/* The start of the entry block: the frame slots, then the leaves of each parameter that arrived as an
 * address. */
static void emit_entry(EmitCx *cx) {
  emit_frame_slots(cx);
  for (uint32_t param = 0; param < cx->func->nparams; param++) {
    if (!emit_is_indirect(cx, cx->func->params[param].ty)) {
      continue;
    }
    MirValue value = cx->func->blocks.ptr[0].params.ptr[param].value;
    if (emit_wide_held(cx, value)) {
      continue; /* read from its address where used */
    }
    char from[24];
    emit_register_name(from, sizeof from, "in", value);
    emit_leaves_at(cx, value, from, true);
  }
  if (cx->unwind_byte) {
    emit_unwinding_address(cx);
  }
  emit_debug_params(cx);
}

/* One block: its label, then its instructions. Each instruction is written first into a builder of its own, since the
 * loads of the held values it reads come before it. */
static bool emit_block(EmitCx *cx, uint32_t block, const uint32_t *last) {
  const MirBlockData *data = &cx->func->blocks.ptr[block];
  MsStrBuild *module_out = cx->out;
  ms_strbuild_printf(cx->out, "b%u:\n", block);
  emit_wide_start(cx, MIR_NONE);
  if (block == 0) {
    emit_entry(cx);
  } else {
    emit_phis(cx, block, last);
  }
  MsStrBuild text = ms_strbuild_new();
  MsStrBuild piece = ms_strbuild_new();
  bool ok = true;
  uint32_t part = 0;
  for (uint32_t index = 0; ok && index <= data->insts.len; index++) {
    const bool last_one = index == data->insts.len;
    const MirInst *inst = last_one ? NULL : &data->insts.ptr[index];
    emit_wide_start(cx, last_one ? MIR_NONE : inst->res);
    ms_strbuild_clear(&piece);
    cx->out = &piece;
    if (last_one) {
      ok = emit_terminator(cx, &data->term, block);
      if (ok) {
        emit_edge_blocks(cx, &data->term, block);
      }
    } else {
      EmitSite site = {block, index, &part};
      ok = emit_instruction(cx, inst, &site);
      if (ok) {
        emit_wide_store(cx, inst->res);
        emit_poison_fills(cx, block, index);
      }
    }
    cx->out = &text;
    const size_t from = ms_strbuild_length(&text);
    if (ok) {
      emit_wide_loads(cx);
      ms_strbuild_append(&text, ms_strbuild_span(&piece));
      emit_debug_place(cx, from, last_one ? data->term_loc : inst->loc);
    }
  }
  cx->out = module_out;
  if (ok) {
    ms_strbuild_append(module_out, ms_strbuild_span(&text));
  }
  ms_strbuild_free(&text);
  ms_strbuild_free(&piece);
  return ok;
}

/* `define <result> @name(<hidden result pointer>, <leaves of each parameter>)`; returns after `nounwind`. */
static void emit_header(EmitCx *cx, uint32_t index, uint32_t subprogram) {
  const MirFunc *func = cx->func;
  MsStrBuild *out = cx->out;
  bool exported = func->linkage == ML_EXPORT || cx->module->entry == index;
  MsSpan result = emit_leaves(cx, func->ret);
  ms_strbuild_printf(out, "define %s%s ", exported ? "" : "internal ",
                     result.len == 1 ? emit_leaf_type(result.ptr[0]) : "void");
  emit_function_symbol(cx, index);
  ms_strbuild_append_byte(out, '(');
  bool first = true;
  if (result.len > 1) {
    ms_strbuild_append_text(out, "ptr %sret");
    first = false;
  }
  for (uint32_t param = 0; param < func->nparams; param++) {
    MirValue value = func->blocks.ptr[0].params.ptr[param].value;
    MsSpan leaves = emit_leaves(cx, func->params[param].ty);
    if (emit_is_indirect(cx, func->params[param].ty)) {
      /* The entry block loads the leaves and nothing else touches the address: a caller's copy that is only
       * read, not kept, and one the callee owns for its whole life. */
      ms_strbuild_printf(out, "%sptr nonnull readonly nocapture align 8 dereferenceable(%u) %%in%u",
                         first ? "" : ", ", emit_slot_bytes(cx, func->params[param].ty), value);
      first = false;
      continue;
    }
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      ms_strbuild_printf(out, "%s%s ", first ? "" : ", ", emit_leaf_type(leaves.ptr[leaf]));
      emit_name(out, value, leaf);
      first = false;
    }
  }
  /* Every function that calls another keeps a frame pointer: the fault walker follows the chain, and a
   * frameless wrapper would drop its caller's frame from the trace. */
  ms_strbuild_append_text(out, ") nounwind noinline");
  /* Windows walks the stack with the system's unwind data, since the frame register does not point at the saved record
   * there; `uwtable` makes llc write it for a function that cannot throw. */
  if (emit_host_windows()) {
    ms_strbuild_append_text(out, " uwtable");
  }
  ms_strbuild_append_text(out, " \"frame-pointer\"=\"non-leaf\" \"disable-tail-calls\"=\"true\"");
  if (cx->pure) {
    ms_strbuild_append_text(out, " willreturn nofree nosync memory(none)");
  }
  if (cx->debug != NULL) {
    ms_strbuild_printf(out, " !dbg !%u", subprogram);
  }
  ms_strbuild_append_text(out, " {\n");
}

/* The pieces each block splits into: its checked operations each end one, and the last piece is what the
 * successors' phis name. Fills `last` with the count per block. */
static void count_pieces(const EmitCx *cx, uint32_t *last) {
  const MirFunc *func = cx->func;
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    last[block] = 0;
    for (uint32_t index = 0; index < data->insts.len; index++) {
      last[block] += emit_pieces(cx->module, func, &data->insts.ptr[index]);
    }
  }
}

/* Writes function `index`. The body is written first into a builder of its own, because the header is written
 * after the instructions have set the state it reads. */
bool emit_function(EmitCx *cx, uint32_t index) {
  const MirFunc *func = cx->func;
  if (!types_ok(cx)) {
    return false;
  }
  size_t bytes = 0;
  if (!ms_size_mul(func->blocks.len + 1, sizeof(uint32_t), &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "block count");
  }
  uint32_t *last = ms_alloc_zeroed(bytes);
  count_pieces(cx, last);
  MsArena scratch = {0};
  cx->framed = mir_framed_closures(&scratch, cx->module, func);
  cx->borrowed = mir_framed_iface_borrows(&scratch, cx->module, func);
  bool *is_iconst = MS_ARENA_NEW_ARRAY(&scratch, bool, func->values.len + 1);
  int64_t *iconst = MS_ARENA_NEW_ARRAY(&scratch, int64_t, func->values.len + 1);
  __builtin_memset(is_iconst, 0, sizeof *is_iconst * (func->values.len + 1));
  for (uint32_t block = 0; block < func->blocks.len; block++) {
    const MirBlockData *data = &func->blocks.ptr[block];
    for (uint32_t at = 0; at < data->insts.len; at++) {
      const MirInst *inst = &data->insts.ptr[at];
      if (inst->op == MOP_IConst && inst->res != MIR_NONE) {
        is_iconst[inst->res] = true;
        iconst[inst->res] = inst->imm.i;
      }
      if (inst->op == MOP_CallRt && inst->res != MIR_NONE && inst->imm.tag == MI_EXT &&
        cx->module->externs.ptr[inst->imm.a].role == MR_UNWINDING) {
        cx->unwind_byte = true;
      }
    }
  }
  cx->is_iconst = is_iconst;
  cx->iconst = iconst;
  emit_index_edges(cx, &scratch);
  const bool *held = emit_wide_plan(cx, &scratch);
  cx->pool = emit_slot_pool(&scratch, cx, held);
  emit_wide_alias(cx);
  uint32_t subprogram = cx->debug != NULL ? emit_debug_subprogram(cx, index) : 0;
  MsStrBuild *module_out = cx->out;
  MsStrBuild body = ms_strbuild_new();
  cx->out = &body;
  bool ok = true;
  for (uint32_t block = 0; ok && block < func->blocks.len; block++) {
    ok = emit_block(cx, block, last);
  }
  cx->out = module_out;
  if (ok) {
    emit_forward_copies(&body);
    emit_drop_dead_definitions(&body);
    emit_header(cx, index, subprogram);
    ms_strbuild_append(module_out, ms_strbuild_span(&body));
    ms_strbuild_append_text(module_out, "}\n\n");
  }
  ms_strbuild_free(&body);
  ms_free(last);
  ms_arena_free(&scratch);
  cx->framed = NULL;
  cx->borrowed = NULL;
  cx->is_iconst = NULL;
  cx->into_start = cx->into_from = cx->into_edge = NULL;
  cx->unwind_byte = false;
  cx->iconst = NULL;
  cx->pool = NULL;
  cx->cell_bytes = NULL;
  cx->cell_escape = NULL;
  cx->ncells = 0;
  emit_wide_end(cx);
  return ok;
}
