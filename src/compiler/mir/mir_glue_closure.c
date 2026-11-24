/* compiler/mir/mir_glue_closure.c: drop and clone entries of closure objects. A capture with a closer is
 * closed in place first; a close that faults posts it and returns, and the drop goes on with the rest of the object. */
#include "compiler/mir/mir_glue_internal.h"

static const MirParam ptr_param = {MIR_PTR, MM_BORROW};

typedef struct Capture {
  MirTy ty;
  int64_t offset;
  bool dropped;     /* a drop leaves work for the capture: it needs one, and no closer took the value */
  bool has_closer;
  uint32_t closer;  /* the function that closes the capture in place */
} Capture;

static bool closer_of(const MirFunc *func, uint32_t capture, uint32_t *close) {
  for (uint32_t index = 0; index < func->ncapture_closers; index++) {
    if (func->capture_closers[index].capture == capture) {
      *close = func->capture_closers[index].func;
      return true;
    }
  }
  return false;
}

/* The captures of closure function `closure`, in the module's arena. */
static Capture *captures_of(MirModule *module, uint32_t closure, uint32_t *count, uint32_t *size) {
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  const MirFunc *func = &module->funcs.ptr[closure];
  const MirClosureLayout layout = mir_closure_layout(&layouts, func);
  Capture *captures = MIRGL_ARRAY(module, Capture, layout.ncaptures);
  for (uint32_t index = 0; index < layout.ncaptures; index++) {
    Capture *capture = &captures[index];
    capture->ty = layout.captures[index].ty;
    capture->offset = layout.captures[index].offset;
    capture->has_closer = closer_of(func, index, &capture->closer);
    capture->dropped = !func->scoped && mir_needs_drop(module, capture->ty) &&
                       (!capture->has_closer || module->funcs.ptr[capture->closer].has_slot_close);
  }
  *count = layout.ncaptures;
  *size = layout.size;
  mir_layouts_free(&layouts);
  return captures;
}

/* Closes capture `capture` in place, shielded from a cancel like every implicit close. */
static void close_capture(MirBuilder *b, MirValue at, const Capture *capture) {
  MirModule *module = b->module;
  const uint32_t shield_in = mirgl_extern(module, "msrt_shield_enter", NULL, 0, MIR_VOID, false);
  const uint32_t shield_out = mirgl_extern(module, "msrt_shield_exit", NULL, 0, MIR_VOID, false);
  (void)mirgl_call_rt(b, shield_in, NULL, 0);
  (void)mirgl_val(b, MOP_Call, &at, 1, mirgl_imm_func(capture->closer), MIR_NONE);
  (void)mirgl_call_rt(b, shield_out, NULL, 0);
}

/* `fn(obj)` that drops the captures of a closure object and frees it (a framed object lives in a stack slot
 * and is not freed). */
uint32_t mirgl_make_closure_drop(MirModule *module, uint32_t closure, bool framed) {
  uint32_t count = 0, size = 0;
  Capture *captures = captures_of(module, closure, &count, &size);
  MirBuilder b;
  mir_b_init(&b, module, mirgl_name(module, module->funcs.len, "closure_drop"), &ptr_param, 1, MIR_VOID);
  MirValue object;
  mir_b_params(&b, &object, 1);
  for (uint32_t index = 0; index < count; index++) {
    const MirValue at = mirgl_ptr_at(&b, object, captures[index].offset);
    if (captures[index].has_closer) {
      close_capture(&b, at, &captures[index]);
    }
    if (captures[index].dropped) {
      mirgl_drop(&b, mirgl_take(&b, at, captures[index].ty));
    }
  }
  if (!framed) {
    mirgl_free(&b, object);
  }
  mir_b_ret(&b, MIR_NONE);
  return mirgl_finish(&b);
}

/* `fn(obj) -> obj`: a new closure object with the same clone and code entries, the heap drop entry, and a
 * clone of every capture. */
uint32_t mirgl_make_closure_clone(MirModule *module, MirGlue *glue, uint32_t closure) {
  uint32_t count = 0, size = 0;
  const Capture *captures = captures_of(module, closure, &count, &size);
  const uint32_t drop = mir_glue_find(glue, MG_CLOSURE_DROP, MIR_VOID, closure, 0);
  const MirTy int_param = MIR_INT;
  const uint32_t alloc = mirgl_extern(module, "msrt_alloc", &int_param, 1, MIR_PTR, true);
  MirBuilder b;
  mir_b_init(&b, module, mirgl_name(module, module->funcs.len, "closure_clone"), &ptr_param, 1, MIR_PTR);
  MirValue src;
  mir_b_params(&b, &src, 1);
  MirValue *copies = MIRGL_ARRAY(module, MirValue, count);
  for (uint32_t index = 0; index < count; index++) {
    const MirValue at = mirgl_ptr_at(&b, src, captures[index].offset);
    copies[index] = mirgl_clone(&b, mirgl_load(&b, at, captures[index].ty));
  }
  const MirValue length = mir_b_iconst(&b, size);
  const MirValue object = mirgl_call_rt(&b, alloc, &length, 1);
  /* The clone and code entries carry over; the drop entry is the heap one even when `src` lives in a frame. */
  const int64_t words[2] = {0, MIRGL_CLOSURE_CODE_OFFSET};
  for (uint32_t index = 0; index < 2; index++) {
    const MirValue word = mirgl_load(&b, mirgl_ptr_at(&b, src, words[index]), MIR_PTR);
    mirgl_put(&b, mirgl_ptr_at(&b, object, words[index]), word);
  }
  const MirValue drop_addr = mirgl_val(&b, MOP_FuncAddr, NULL, 0, mirgl_imm_func(drop), MIR_PTR);
  mirgl_put(&b, mirgl_ptr_at(&b, object, 8), drop_addr);
  for (uint32_t index = 0; index < count; index++) {
    mirgl_put(&b, mirgl_ptr_at(&b, object, captures[index].offset), copies[index]);
  }
  mir_b_ret(&b, object);
  return mirgl_finish(&b);
}
