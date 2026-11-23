/* The `inline` pass, dead functions: removes the functions no root reaches and renumbers the rest. */
#include "compiler/opt/opt_inline.h"

/* ---- dead functions ---- */

static void il_push_root(uint32_t *stack, uint32_t *n, uint32_t f) {
  stack[(*n)++] = f;
}

/* Marks every function a root reaches; false when there are no roots. */
static bool il_mark_live(MsArena *arena, const MirModule *m, bool *live) {
  size_t cap = (size_t)m->funcs.len + 1;
  for (uint32_t v = 0; v < m->vtables.len; v++) {
    cap += (size_t)m->vtables.ptr[v].nmethods + 1;
  }
  cap += 2 * (size_t)m->desc_glue.len;
  for (uint32_t t = 0; t < m->type_defs.len; t++) {
    cap += m->type_defs.ptr[t].nfields;
  }
  for (uint32_t i = 0; i < m->funcs.len; i++) {
    cap += m->funcs.ptr[i].ncapture_closers;
    for (uint32_t b = 0; b < m->funcs.ptr[i].blocks.len; b++) {
      cap += m->funcs.ptr[i].blocks.ptr[b].insts.len;
    }
  }
  uint32_t *stack = MS_ARENA_NEW_ARRAY(arena, uint32_t, cap + 1);
  uint32_t n = 0;
  if (m->entry != MIR_NONE) {
    il_push_root(stack, &n, m->entry);
  }
  if (m->close != MIR_NONE) {
    il_push_root(stack, &n, m->close);
  }
  for (uint32_t i = 0; i < m->funcs.len; i++) {
    if (m->funcs.ptr[i].linkage == ML_EXPORT) {
      il_push_root(stack, &n, i);
    }
  }
  for (uint32_t v = 0; v < m->vtables.len; v++) {
    for (uint32_t k = 0; k < m->vtables.ptr[v].nmethods; k++) {
      il_push_root(stack, &n, m->vtables.ptr[v].methods[k]);
    }
    if (m->vtables.ptr[v].close_drop != 0) {
      il_push_root(stack, &n, m->vtables.ptr[v].close_drop - 1);
    }
  }
  for (uint32_t g = 0; g < m->desc_glue.len; g++) {
    il_push_root(stack, &n, m->desc_glue.ptr[g].eq);
    il_push_root(stack, &n, m->desc_glue.ptr[g].hash);
  }
  /* A field default is named by the shape table of its type, which is made after this pass. */
  for (uint32_t t = 0; t < m->type_defs.len; t++) {
    for (uint32_t f = 0; f < m->type_defs.ptr[t].nfields; f++) {
      if (m->type_defs.ptr[t].fields[f].default_fn1 != 0) {
        il_push_root(stack, &n, m->type_defs.ptr[t].fields[f].default_fn1 - 1);
      }
    }
  }
  /* The functions a shape table calls for a type's own text and JSON form. */
  for (uint32_t t = 0; t < m->type_defs.len; t++) {
    if (m->type_defs.ptr[t].text_fn1 != 0) {
      il_push_root(stack, &n, m->type_defs.ptr[t].text_fn1 - 1);
    }
    if (m->type_defs.ptr[t].json_fn1 != 0) {
      il_push_root(stack, &n, m->type_defs.ptr[t].json_fn1 - 1);
    }
  }
  for (uint32_t a = 0; a < m->alts.len; a++) {
    if (m->alts.ptr[a].text_fn1 != 0) {
      il_push_root(stack, &n, m->alts.ptr[a].text_fn1 - 1);
    }
    if (m->alts.ptr[a].tree_fn1 != 0) {
      il_push_root(stack, &n, m->alts.ptr[a].tree_fn1 - 1);
    }
    if (m->alts.ptr[a].json_fn1 != 0) {
      il_push_root(stack, &n, m->alts.ptr[a].json_fn1 - 1);
    }
  }
  for (uint32_t o = 0; o < m->obj_hooks.len; o++) {
    if (m->obj_hooks.ptr[o].text_fn1 != 0) {
      il_push_root(stack, &n, m->obj_hooks.ptr[o].text_fn1 - 1);
    }
    if (m->obj_hooks.ptr[o].json_fn1 != 0) {
      il_push_root(stack, &n, m->obj_hooks.ptr[o].json_fn1 - 1);
    }
  }
  const bool any = n > 0;
  while (n > 0) {
    const uint32_t i = stack[--n];
    if (live[i]) {
      continue;
    }
    live[i] = true;
    const MirFunc *f = &m->funcs.ptr[i];
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      for (uint32_t k = 0; k < f->blocks.ptr[b].insts.len; k++) {
        const MirInst *in = &f->blocks.ptr[b].insts.ptr[k];
        if (in->imm.tag == MI_FUNC) {
          il_push_root(stack, &n, in->imm.a);
        }
      }
    }
    for (uint32_t k = 0; k < f->ncapture_closers; k++) {
      il_push_root(stack, &n, f->capture_closers[k].func);
    }
  }
  return any;
}

static void il_renumber(MirModule *m, const uint32_t *map) {
  for (uint32_t i = 0; i < m->funcs.len; i++) {
    MirFunc *f = &m->funcs.ptr[i];
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      for (uint32_t k = 0; k < f->blocks.ptr[b].insts.len; k++) {
        MirInst *in = &f->blocks.ptr[b].insts.ptr[k];
        if (in->imm.tag == MI_FUNC) {
          in->imm.a = map[in->imm.a];
        }
      }
    }
    for (uint32_t k = 0; k < f->ncapture_closers; k++) {
      f->capture_closers[k].func = map[f->capture_closers[k].func];
    }
  }
  for (uint32_t v = 0; v < m->vtables.len; v++) {
    for (uint32_t k = 0; k < m->vtables.ptr[v].nmethods; k++) {
      m->vtables.ptr[v].methods[k] = map[m->vtables.ptr[v].methods[k]];
    }
    if (m->vtables.ptr[v].close_drop != 0) {
      m->vtables.ptr[v].close_drop = map[m->vtables.ptr[v].close_drop - 1] + 1;
    }
  }
  for (uint32_t g = 0; g < m->desc_glue.len; g++) {
    m->desc_glue.ptr[g].eq = map[m->desc_glue.ptr[g].eq];
    m->desc_glue.ptr[g].hash = map[m->desc_glue.ptr[g].hash];
  }
  for (uint32_t t = 0; t < m->type_defs.len; t++) {
    for (uint32_t f = 0; f < m->type_defs.ptr[t].nfields; f++) {
      MirField *field = &m->type_defs.ptr[t].fields[f];
      field->default_fn1 = field->default_fn1 != 0 ? map[field->default_fn1 - 1] + 1 : 0;
    }
  }
  for (uint32_t t = 0; t < m->type_defs.len; t++) {
    MirTypeDef *def = &m->type_defs.ptr[t];
    def->text_fn1 = def->text_fn1 != 0 ? map[def->text_fn1 - 1] + 1 : 0;
    def->json_fn1 = def->json_fn1 != 0 ? map[def->json_fn1 - 1] + 1 : 0;
  }
  for (uint32_t a = 0; a < m->alts.len; a++) {
    MirAltDef *def = &m->alts.ptr[a];
    def->tree_fn1 = def->tree_fn1 != 0 ? map[def->tree_fn1 - 1] + 1 : 0;
    def->text_fn1 = def->text_fn1 != 0 ? map[def->text_fn1 - 1] + 1 : 0;
    def->json_fn1 = def->json_fn1 != 0 ? map[def->json_fn1 - 1] + 1 : 0;
  }
  for (uint32_t o = 0; o < m->obj_hooks.len; o++) {
    MirObjHook *hook = &m->obj_hooks.ptr[o];
    hook->text_fn1 = hook->text_fn1 != 0 ? map[hook->text_fn1 - 1] + 1 : 0;
    hook->json_fn1 = hook->json_fn1 != 0 ? map[hook->json_fn1 - 1] + 1 : 0;
  }
  m->entry = m->entry == MIR_NONE ? MIR_NONE : map[m->entry];
  m->close = m->close == MIR_NONE ? MIR_NONE : map[m->close];
}

/* Moves the live functions down in order, `map` taking each old id to its new one. */
static void il_compact_funcs(MirModule *m, const bool *live, uint32_t *map) {
  uint32_t next = 0;
  for (uint32_t i = 0; i < m->funcs.len; i++) {
    map[i] = MIR_NONE;
    if (live[i]) {
      map[i] = next;
      m->funcs.ptr[next++] = m->funcs.ptr[i];
    } else {
      mir_func_release(&m->funcs.ptr[i]);
    }
  }
  m->funcs.len = next;
}

/* Removes functions no root can reach and renumbers the rest. */
bool opt_inline_remove_dead(MirModule *m) {
  MsArena arena = ms_arena_new();
  bool *live = MS_ARENA_NEW_ARRAY(&arena, bool, m->funcs.len);
  const bool rooted = il_mark_live(&arena, m, live);
  bool all = true;
  for (uint32_t i = 0; i < m->funcs.len; i++) {
    all = all && live[i];
  }
  if (!rooted || all) {
    ms_arena_free(&arena);
    return false;
  }
  uint32_t *map = MS_ARENA_NEW_ARRAY(&arena, uint32_t, m->funcs.len);
  il_compact_funcs(m, live, map);
  il_renumber(m, map);
  mir_funcs_reindex(m);
  ms_arena_free(&arena);
  return true;
}
