/* compiler/mir/mir_glue_build.c: the table of made glue and the emit helpers the glue builders share. */
#include "base/strbuild.h"
#include "compiler/mir/mir_glue_internal.h"

/* ---- the table of what was made ---- */

void mir_glue_free(MirGlue *glue) {
  mir_glue_entry_list_free(&glue->entries);
  mir_idlist_free(&glue->bodies);
}

uint32_t mir_glue_find(const MirGlue *glue, MirGlueKind kind, MirTy ty, uint32_t a, uint32_t b) {
  for (size_t index = 0; index < glue->entries.len; index++) {
    const MirGlueEntry *entry = &glue->entries.ptr[index];
    if (entry->kind == kind && entry->ty == ty && entry->a == a && entry->b == b) {
      return entry->func;
    }
  }
  return MIR_NONE;
}

void mirgl_record(MirGlue *glue, MirGlueKind kind, MirTy ty, uint32_t a, uint32_t b, uint32_t func) {
  mir_glue_entry_list_push(&glue->entries,
                           (MirGlueEntry){.kind = (uint8_t)kind, .a = a, .b = b, .ty = ty, .func = func});
}

uint32_t mirgl_count(const MirGlue *glue, MirGlueKind kind) {
  uint32_t count = 0;
  for (size_t index = 0; index < glue->entries.len; index++) {
    count += glue->entries.ptr[index].kind == kind;
  }
  return count;
}

/* ---- emit helpers ---- */

MirValue mirgl_val(MirBuilder *b, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty) {
  return mir_b_emit(b, op, args, nargs, imm, ty);
}

MirImm mirgl_imm_ty(MirTy ty) {
  return (MirImm){.tag = MI_TY, .a = ty};
}

MirImm mirgl_imm_func(uint32_t func) {
  return (MirImm){.tag = MI_FUNC, .a = func};
}

MirValue mirgl_ptr_at(MirBuilder *b, MirValue base, int64_t offset) {
  if (offset == 0) {
    return base;
  }
  const MirValue args[2] = {base, mir_b_iconst(b, offset)};
  return mirgl_val(b, MOP_PtrAdd, args, 2, (MirImm){0}, MIR_PTR);
}

MirValue mirgl_clone(MirBuilder *b, MirValue value) {
  return mirgl_val(b, MOP_Clone, &value, 1, (MirImm){0}, mir_b_ty(b, value));
}

MirValue mirgl_take(MirBuilder *b, MirValue at, MirTy ty) {
  return mirgl_val(b, MOP_Take, &at, 1, mirgl_imm_ty(ty), ty);
}

MirValue mirgl_load(MirBuilder *b, MirValue at, MirTy ty) {
  return mirgl_val(b, MOP_Load, &at, 1, mirgl_imm_ty(ty), ty);
}

void mirgl_put(MirBuilder *b, MirValue to, MirValue value) {
  const MirValue args[2] = {to, value};
  (void)mirgl_val(b, MOP_Put, args, 2, (MirImm){0}, MIR_NONE);
}

MirValue mirgl_slot(MirBuilder *b, MirTy ty) {
  return mirgl_val(b, MOP_Slot, NULL, 0, mirgl_imm_ty(ty), MIR_PTR);
}

void mirgl_drop(MirBuilder *b, MirValue value) {
  (void)mirgl_val(b, MOP_Drop, &value, 1, (MirImm){0}, MIR_NONE);
}

void mirgl_free(MirBuilder *b, MirValue value) {
  (void)mirgl_val(b, MOP_Free, &value, 1, (MirImm){0}, MIR_NONE);
}

MirValue mirgl_alt_tag(MirBuilder *b, MirValue object) {
  return mirgl_val(b, MOP_AltTag, &object, 1, (MirImm){0}, MIR_INT);
}

MirValue mirgl_alt_get(MirBuilder *b, uint32_t alt, uint32_t case_index, uint32_t field, MirValue object) {
  const MirTy ty = b->module->alts.ptr[alt].cases[case_index].fields[field].ty;
  const MirImm imm = {.tag = MI_ALTFIELD, .a = alt, .b = case_index, .c = field};
  return mirgl_val(b, MOP_AltGet, &object, 1, imm, ty);
}

void mirgl_alt_release(MirBuilder *b, uint32_t alt, uint32_t case_index, uint32_t mask, MirValue object) {
  const MirImm imm = {.tag = MI_ALTMASK, .a = alt, .b = case_index, .c = mask};
  (void)mirgl_val(b, MOP_AltRelease, &object, 1, imm, MIR_NONE);
}

MirValue mirgl_alt_new(MirBuilder *b, uint32_t alt, uint32_t case_index, const MirValue *fields,
                       uint32_t count) {
  const MirImm imm = {.tag = MI_CASE, .a = alt, .b = case_index};
  return mirgl_val(b, MOP_AltNew, fields, count, imm, mir_ty_alt(b->module, alt));
}

MirValue mirgl_opt_is_some(MirBuilder *b, MirValue opt) {
  return mirgl_val(b, MOP_OptIsSome, &opt, 1, (MirImm){0}, MIR_BOOL);
}

MirValue mirgl_opt_payload(MirBuilder *b, MirOp op, MirValue opt) {
  MirTy inner = MIR_NONE;
  (void)mirgl_is_opt(b->module, mir_b_ty(b, opt), &inner);
  return mirgl_val(b, op, &opt, 1, (MirImm){0}, inner);
}

MirValue mirgl_list_len(MirBuilder *b, MirValue list) {
  return mirgl_val(b, MOP_ListLen, &list, 1, (MirImm){0}, MIR_INT);
}

MirValue mirgl_call_rt(MirBuilder *b, uint32_t external, const MirValue *args, uint32_t nargs) {
  return mir_b_call_rt(b, external, args, nargs);
}

uint32_t mirgl_finish(MirBuilder *b) {
  uint32_t id = MIR_NONE;
  return mir_b_finish(b, &id) ? id : MIR_NONE;
}

MsName mirgl_name(MirModule *module, size_t n, const char *suffix) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_printf(&text, "ms.glue.mir.%zu.%s", n, suffix);
  const MsName name = mir_name(module, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

uint32_t mirgl_extern(MirModule *module, const char *name, const MirTy *params, uint32_t nparams, MirTy ret,
                      bool fresh) {
  const uint32_t id = mir_extern_get(module, ms_span_of_text(name), params, nparams, ret, false, MR_NONE);
  if (fresh) {
    module->externs.ptr[id].fresh = true;
  }
  return id;
}

void *mirgl_array(MirModule *module, size_t element_size, size_t alignment, size_t count) {
  return ms_arena_alloc_array(&module->arena, element_size, alignment, count);
}
