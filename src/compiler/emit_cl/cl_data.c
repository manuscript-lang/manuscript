/* Owns static data: the symbols MIR decided on (descriptors, vtables, globals, long literals), defined in the object,
 * and the operations that name them. */
#include "compiler/emit_cl/cl_cx.h"

#include <string.h>

#include "base/alloc.h"

/* The runtime's data symbol `name`, declared on first use. */
static ms_cl_data runtime_data(ClModule *mod, MsSpan name) {
  for (uint32_t index = 0; index < mod->nruntime; index++) {
    if (ms_span_equal(mod->runtime[index].name, name)) {
      return mod->runtime[index].data;
    }
  }
  if (mod->nruntime == mod->cap_runtime) {
    mod->cap_runtime = mod->cap_runtime == 0 ? 16 : mod->cap_runtime * 2;
    mod->runtime = ms_realloc(mod->runtime, mod->cap_runtime * sizeof *mod->runtime);
  }
  MsStrBuild text = ms_strbuild_new();
  const ms_cl_data data = ms_cl_declare_data(mod->cl, cl_c_name(&text, name), MS_CL_IMPORT, 1, 0);
  ms_strbuild_free(&text);
  mod->runtime[mod->nruntime++] = (struct ClRuntimeData){name, data};
  return data;
}

static ms_cl_reloc reloc_of(ClModule *mod, const MirReloc *reloc) {
  switch (reloc->to.kind) {
  case MREF_DATA:
    return (ms_cl_reloc){.offset = reloc->offset, .kind = 1, .target = mod->syms[reloc->to.index].id};
  case MREF_FUNC:
    return (ms_cl_reloc){.offset = reloc->offset, .kind = 0, .target = mod->funcs[reloc->to.index].id};
  default:
    return (ms_cl_reloc){.offset = reloc->offset, .kind = 1, .target = runtime_data(mod, reloc->to.runtime).id};
  }
}

void cl_define_data(ClModule *mod) {
  const MirData *data = mod->data;
  if (data == NULL) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  mod->syms = ms_alloc((data->syms.len + 1) * sizeof(ms_cl_data));
  for (uint32_t index = 0; index < data->syms.len; index++) {
    const MirDataSym *sym = &data->syms.ptr[index];
    mod->syms[index] = ms_cl_declare_data(mod->cl, cl_c_name(&text, sym->name), MS_CL_LOCAL, sym->writable ? 1 : 0, 0);
  }
  for (uint32_t index = 0; index < data->syms.len; index++) {
    const MirDataSym *sym = &data->syms.ptr[index];
    ms_cl_reloc *relocs = ms_alloc((sym->nrelocs + 1) * sizeof(ms_cl_reloc));
    for (uint32_t at = 0; at < sym->nrelocs; at++) {
      relocs[at] = reloc_of(mod, &sym->relocs[at]);
    }
    uint8_t *bytes = NULL;
    if (sym->bytes.len != 0) {
      bytes = ms_alloc_zeroed(sym->size > sym->bytes.len ? sym->size : sym->bytes.len);
      memcpy(bytes, sym->bytes.ptr, sym->bytes.len);
    }
    ms_cl_define_data(mod->cl, mod->syms[index], bytes, sym->size, sym->align, relocs, sym->nrelocs);
    ms_free(bytes);
    ms_free(relocs);
  }
  ms_strbuild_free(&text);
}

void cl_free_data(ClModule *mod) {
  ms_free(mod->syms);
  ms_free(mod->runtime);
  mod->syms = NULL;
  mod->runtime = NULL;
}

ms_cl_val cl_ref_address(ClCx *cx, MirRef ref) {
  switch (ref.kind) {
  case MREF_DATA:
    return ms_cl_data_addr(cx->fb, cx->mod->syms[ref.index]);
  case MREF_FUNC:
    return ms_cl_func_addr(cx->fb, cx->mod->funcs[ref.index]);
  default:
    return ms_cl_data_addr(cx->fb, runtime_data(cx->mod, ref.runtime));
  }
}

static bool typedesc(ClCx *cx, const MirInst *inst) {
  if (cx->mod->data == NULL) {
    cx->why = "no static data";
    return false;
  }
  const MirRef ref = mir_data_desc(cx->mod->data, (MirTy)inst->imm.a);
  if (ref.kind == MREF_RUNTIME && ref.runtime.len == 0) {
    cx->why = "typedesc of a type the data table did not see";
    return false;
  }
  cl_set(cx, inst->res, 0, cl_ref_address(cx, ref));
  return true;
}

static bool shape_table(ClCx *cx, const MirInst *inst) {
  const MirRef ref = cx->mod->data != NULL ? mir_data_shape(cx->mod->data, (MirTy)inst->imm.a)
                                           : (MirRef){.kind = MREF_RUNTIME};
  if (ref.kind == MREF_RUNTIME) {
    cx->why = "shape of a type the data table did not see";
    return false;
  }
  cl_set(cx, inst->res, 0, cl_ref_address(cx, ref));
  return true;
}

/* `str`: a short literal is two constant words; a long one is the address of its bytes and a tag. */
static bool string_literal(ClCx *cx, const MirInst *inst) {
  bool is_static = false;
  uint64_t lo = 0;
  uint64_t hi = 0;
  const uint32_t id = inst->imm.a;
  mir_str_lit_words(ms_names_span(&cx->module->strings, id), &is_static, &lo, &hi);
  if (!is_static) {
    cl_set(cx, inst->res, 0, cl_const(cx, (int64_t)lo));
  } else if (cx->mod->data == NULL || cx->mod->data->strings.ptr[id] == MIR_NONE) {
    cx->why = "str without static data";
    return false;
  } else {
    cl_set(cx, inst->res, 0, ms_cl_data_addr(cx->fb, cx->mod->syms[cx->mod->data->strings.ptr[id]]));
  }
  cl_set(cx, inst->res, 1, cl_const(cx, (int64_t)hi));
  return true;
}

static bool global(ClCx *cx, const MirInst *inst) {
  if (cx->mod->data == NULL) {
    cx->why = "no static data";
    return false;
  }
  const ms_cl_val base = ms_cl_data_addr(cx->fb, cx->mod->syms[cx->mod->data->globals.ptr[inst->imm.a]]);
  const bool get = inst->op == MOP_GlobalGet;
  cl_leaves_at(cx, get ? inst->res : inst->args[0], base, get);
  return true;
}

bool cl_data_op(ClCx *cx, const MirInst *inst, bool *handled) {
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
