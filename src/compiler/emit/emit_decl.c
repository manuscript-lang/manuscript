/* Owns the declarations at the end of a module: the runtime functions it lists, the allocator and fault
 * functions the emitter calls itself, and the LLVM intrinsics. */
#include "compiler/emit/emit_decl.h"

/* The extern the module declares as `name`, or MIR_NONE. */
static uint32_t extern_named(const EmitCx *cx, const char *name) {
  MsSpan wanted = ms_span_of_text(name);
  for (uint32_t index = 0; index < cx->module->externs.len; index++) {
    if (ms_span_equal(ms_names_span(&cx->module->names, cx->module->externs.ptr[index].name), wanted)) {
      return index;
    }
  }
  return MIR_NONE;
}

/* The allocator functions the emitter calls itself (closure objects, `free`), declared with the same
 * word-sized signatures as every runtime function unless the module lists them. */
static void declare_heap(const EmitCx *cx) {
  static const struct {
    const char *name;
    const char *declaration;
  } heap[] = {
      {"msrt_alloc", "declare i64 @msrt_alloc(i64)\n"},
      {"msrt_realloc", "declare i64 @msrt_realloc(i64, i64)\n"},
      {"msrt_free", "declare void @msrt_free(ptr)\n"},
      {"msrt_string_free", "declare void @msrt_string_free(ptr)\n"},
  };
  for (size_t index = 0; index < MS_COUNT_OF(heap); index++) {
    if (extern_named(cx, heap[index].name) == MIR_NONE) {
      ms_strbuild_append_text(cx->out, heap[index].declaration);
    }
  }
}

static const char *leaf_register_type(EmitCx *cx, const MirExtern *def, MirLeaf leaf) {
  return leaf == MIR_LEAF_F32 && emit_extern_is_c(cx, def) ? "float" : emit_leaf_type(leaf);
}

/* One `declare` for the runtime function `def`, in the signature `call_runtime` calls it with. A function that
 * never returns says so, so the code after a call of it is unreachable. */
static void declare_extern(EmitCx *cx, const MirExtern *def) {
  MsStrBuild *out = cx->out;
  MsSpan result = emit_leaves(cx, def->ret);
  bool direct = emit_rt_direct(cx, def->ret);
  const bool option = emit_rt_scalar_option(cx, def->ret);
  const char *type = option ? "i8" : (direct && result.len == 1 ? leaf_register_type(cx, def, result.ptr[0]) : "void");
  ms_strbuild_printf(out, "declare %s ", type);
  emit_symbol(out, ms_names_span(&cx->module->names, def->name));
  ms_strbuild_append_byte(out, '(');
  bool first = true;
  for (uint32_t param = 0; param < def->nparams; param++) {
    MirTy param_type = def->params[param].ty;
    if (param_type == MIR_PTR || !emit_rt_direct(cx, param_type)) {
      ms_strbuild_printf(out, "%sptr", first ? "" : ", ");
      first = false;
      continue;
    }
    MsSpan leaves = emit_leaves(cx, param_type);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      ms_strbuild_printf(out, "%s%s", first ? "" : ", ", leaf_register_type(cx, def, leaves.ptr[leaf]));
      first = false;
    }
  }
  if (!direct || option) {
    ms_strbuild_printf(out, "%sptr", first ? "" : ", ");
  }
  ms_strbuild_printf(out, ")%s\n", def->noreturn ? " noreturn" : "");
}

static void declare_externs(EmitCx *cx) {
  const MirModule *module = cx->module;
  for (uint32_t index = 0; index < module->externs.len; index++) {
    const MirExtern *def = &module->externs.ptr[index];
    bool listed = false; /* the module keeps one entry per signature, so a name may be listed twice */
    for (uint32_t earlier = 0; earlier < index && !listed; earlier++) {
      listed = module->externs.ptr[earlier].name == def->name;
    }
    if (!listed) {
      declare_extern(cx, def);
    }
  }
}

/* The fault functions the emitter calls itself, unless the module lists one (then `declare_externs` did). */
static void declare_faults(const EmitCx *cx) {
  static const struct {
    const char *name;
    const char *params;
  } faults[] = {
      {"msrt_fault_posted", ""},
  };
  static const struct {
    const char *name;
    const char *params;
  } posts[] = {
      {"msrt_post_int_overflow", ""}, {"msrt_post_int_range", ""},          {"msrt_post_div_zero", ""},
      {"msrt_post_rem_zero", ""},     {"msrt_post_div_overflow", "i64, i64"}, {"msrt_post_index", "i64, i64"},
      {"msrt_post_unwrap_none", ""},
  };
  for (size_t index = 0; index < MS_COUNT_OF(posts); index++) {
    if (extern_named(cx, posts[index].name) != MIR_NONE) {
      continue;
    }
    ms_strbuild_printf(cx->out, "declare void @%s(%s) cold nounwind\n", posts[index].name, posts[index].params);
  }
  for (size_t index = 0; index < MS_COUNT_OF(faults); index++) {
    if (extern_named(cx, faults[index].name) == MIR_NONE) {
      ms_strbuild_printf(cx->out, "declare void @%s(%s) cold noreturn nounwind\n", faults[index].name,
                         faults[index].params);
    }
  }
}

static const char intrinsics[] =
    "declare i64 @llvm.fptosi.sat.i64.f64(double)\n"
    "declare ptr @llvm.frameaddress.p0(i32)\n"
    "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)\n"
    "declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1)\n"
    "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)\n"
    "declare void @llvm.dbg.value(metadata, metadata, metadata)\n"
    /* The sized form: LLVM 18 to 21 need it and the pinned LLVM upgrades it to the unsized one. */
    "declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture)\n"
    "declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture)\n"
    "@msrt_ascii_chars = external global [0 x i8]\n"
    "declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.uadd.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.usub.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.umul.with.overflow.i64(i64, i64)\n"
    "declare i64 @llvm.fshl.i64(i64, i64, i64)\n"
    "declare i64 @llvm.fshr.i64(i64, i64, i64)\n"
    "declare i64 @llvm.ctlz.i64(i64, i1)\n"
    "declare i64 @llvm.cttz.i64(i64, i1)\n"
    "declare i64 @llvm.ctpop.i64(i64)\n"
    "declare double @llvm.sqrt.f64(double)\n"
    "declare double @llvm.fabs.f64(double)\n"
    "declare double @llvm.floor.f64(double)\n"
    "declare double @llvm.ceil.f64(double)\n"
    "declare double @llvm.trunc.f64(double)\n";

void emit_declarations(EmitCx *cx) {
  declare_externs(cx);
  declare_heap(cx);
  declare_faults(cx);
  ms_strbuild_append_text(cx->out, intrinsics);
}
