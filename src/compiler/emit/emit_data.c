/* Owns static data: the definitions MIR decided on, and the operations that name them. */
#include "compiler/emit/emit_cx.h"

/* The address a relocation or a data reference names, as an LLVM constant. */
static void write_ref(const EmitCx *cx, MirRef ref) {
  switch (ref.kind) {
  case MREF_DATA:
    emit_symbol(cx->out, cx->data->syms.ptr[ref.index].name);
    return;
  case MREF_FUNC:
    emit_function_symbol(cx, ref.index);
    return;
  default:
    emit_symbol(cx->out, ref.runtime);
  }
}

/* `typedesc`: the address of the descriptor for the type, as a word. */
static bool typedesc(EmitCx *cx, const MirInst *inst) {
  if (cx->data == NULL) {
    cx->why = "no static data";
    return false;
  }
  MirRef ref = mir_data_desc(cx->data, (MirTy)inst->imm.a);
  if (ref.kind == MREF_RUNTIME && ref.runtime.len == 0) {
    cx->why = "typedesc of a type the data table did not see";
    return false;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = ptrtoint ptr ", inst->res);
  write_ref(cx, ref);
  ms_strbuild_append_text(cx->out, " to i64\n");
  return true;
}

/* `shape`: the address of the ShapeTable of the type, as a word. */
static bool shape_table(EmitCx *cx, const MirInst *inst) {
  const MirRef ref = cx->data != NULL ? mir_data_shape(cx->data, (MirTy)inst->imm.a) : (MirRef){.kind = MREF_RUNTIME};
  if (ref.kind == MREF_RUNTIME) {
    cx->why = "shape of a type the data table did not see";
    return false;
  }
  ms_strbuild_printf(cx->out, "  %%v%u = ptrtoint ptr ", inst->res);
  write_ref(cx, ref);
  ms_strbuild_append_text(cx->out, " to i64\n");
  return true;
}

/* `str`: a short literal is two constant words; a long one is the address of its bytes and a tag. */
static bool string_literal(EmitCx *cx, const MirInst *inst) {
  bool is_static = false;
  uint64_t lo = 0;
  uint64_t hi = 0;
  uint32_t id = inst->imm.a;
  mir_str_lit_words(ms_names_span(&cx->module->strings, id), &is_static, &lo, &hi);
  if (!is_static) {
    ms_strbuild_printf(cx->out, "  %%v%u = add i64 %lld, 0\n", inst->res, (long long)lo);
  } else if (cx->data == NULL || cx->data->strings.ptr[id] == MIR_NONE) {
    cx->why = "str without static data";
    return false;
  } else {
    ms_strbuild_printf(cx->out, "  %%v%u = ptrtoint ptr ", inst->res);
    write_ref(cx, (MirRef){MREF_DATA, cx->data->strings.ptr[id], ms_span_of(NULL, 0)});
    ms_strbuild_append_text(cx->out, " to i64\n");
  }
  ms_strbuild_printf(cx->out, "  %%v%u.1 = add i64 %lld, 0\n", inst->res, (long long)hi);
  return true;
}

/* `global.get`, `global.set`: the leaves of the value at the global's address. */
static bool global(EmitCx *cx, const MirInst *inst) {
  if (cx->data == NULL) {
    cx->why = "no static data";
    return false;
  }
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out, "  %%g%u = getelementptr i8, ptr ", number);
  emit_symbol(cx->out, cx->data->syms.ptr[cx->data->globals.ptr[inst->imm.a]].name);
  ms_strbuild_append_text(cx->out, ", i64 0\n");
  char base[24];
  emit_register_name(base, sizeof base, "g", number);
  bool get = inst->op == MOP_GlobalGet;
  emit_leaves_at(cx, get ? inst->res : inst->args[0], base, get);
  return true;
}

bool emit_data_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  (void)site;
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_TypeDesc:
    return typedesc(cx, inst);
  case MOP_Shape:
    return shape_table(cx, inst);
  case MOP_StrLit:
    return string_literal(cx, inst);
  case MOP_GlobalGet:
  case MOP_GlobalSet:
    return global(cx, inst);
  default:
    *handled = false;
    return true;
  }
}

/* The words of a data symbol: its bytes with each relocation's address in place. */
static void write_words(const EmitCx *cx, const MirDataSym *sym) {
  MsStrBuild *out = cx->out;
  uint32_t words = (sym->size + 7) / 8; /* the last word is zero padded */
  ms_strbuild_printf(out, "[%u x i64] [", words);
  for (uint32_t word = 0; word < words; word++) {
    const MirReloc *reloc = NULL;
    for (uint32_t index = 0; index < sym->nrelocs; index++) {
      if (sym->relocs[index].offset == word * 8) {
        reloc = &sym->relocs[index];
      }
    }
    ms_strbuild_printf(out, "%si64 ", word == 0 ? "" : ", ");
    if (reloc != NULL) {
      ms_strbuild_append_text(out, "ptrtoint (ptr ");
      write_ref(cx, reloc->to);
      ms_strbuild_append_text(out, " to i64)");
      continue;
    }
    uint64_t value = 0;
    for (uint32_t byte = 0; byte < 8 && word * 8 + byte < sym->size && word * 8 + byte < sym->bytes.len; byte++) {
      value |= (uint64_t)sym->bytes.ptr[word * 8 + byte] << (8 * byte);
    }
    ms_strbuild_printf(out, "%lld", (long long)value);
  }
  ms_strbuild_append_byte(out, ']');
}

/* The runtime's descriptors of the scalar types, which code (a `typedesc`) and data both name. */
static const char *const runtime_descs[] = {"msrt_desc_int",  "msrt_desc_float",  "msrt_desc_float32",
                                            "msrt_desc_bool", "msrt_desc_string", "msrt_desc_bytes"};

static void declare_runtime_symbol(EmitCx *cx, MsSpan name) {
  emit_symbol(cx->out, name);
  ms_strbuild_append_text(cx->out, " = external global i8\n");
}

/* Whether the relocations before (`sym`, `reloc`) already name runtime symbol `name`. */
static bool runtime_seen(const MirData *data, uint32_t sym, uint32_t reloc, MsSpan name) {
  for (uint32_t index = 0; index <= sym; index++) {
    uint32_t end = index < sym ? data->syms.ptr[index].nrelocs : reloc;
    for (uint32_t at = 0; at < end; at++) {
      MirRef other = data->syms.ptr[index].relocs[at].to;
      if (other.kind == MREF_RUNTIME && ms_span_equal(other.runtime, name)) {
        return true;
      }
    }
  }
  return false;
}

static bool is_runtime_desc(MsSpan name) {
  for (size_t index = 0; index < MS_COUNT_OF(runtime_descs); index++) {
    if (ms_span_equal(name, ms_span_of_text(runtime_descs[index]))) {
      return true;
    }
  }
  return false;
}

void emit_define_data(EmitCx *cx) {
  const MirData *data = cx->data;
  if (data == NULL) {
    return;
  }
  for (size_t index = 0; index < MS_COUNT_OF(runtime_descs); index++) {
    declare_runtime_symbol(cx, ms_span_of_text(runtime_descs[index]));
  }
  for (uint32_t sym = 0; sym < data->syms.len; sym++) {
    for (uint32_t reloc = 0; reloc < data->syms.ptr[sym].nrelocs; reloc++) {
      MirRef ref = data->syms.ptr[sym].relocs[reloc].to;
      if (ref.kind == MREF_RUNTIME && !is_runtime_desc(ref.runtime) && !runtime_seen(data, sym, reloc, ref.runtime)) {
        declare_runtime_symbol(cx, ref.runtime);
      }
    }
  }
  for (uint32_t index = 0; index < data->syms.len; index++) {
    const MirDataSym *sym = &data->syms.ptr[index];
    emit_symbol(cx->out, sym->name);
    ms_strbuild_printf(cx->out, " = hidden %s ", sym->writable ? "global" : "constant");
    if (sym->bytes.len == 0 && sym->nrelocs == 0) {
      ms_strbuild_printf(cx->out, "[%u x i8] zeroinitializer", sym->size);
    } else {
      write_words(cx, sym);
    }
    ms_strbuild_printf(cx->out, ", align %u\n", sym->align);
  }
}
