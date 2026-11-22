/* compiler/lower/lower_entry.c: the process entry. It returns the exit status, so a `main` that returns nothing exits
 * 0, and a `main` that returns a Result exits 0 on success and, on an error, writes `error: <message>` to standard
 * error and exits 1. */
#include "compiler/lower/lower_internal.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_builder.h"

enum { OK_CASE = 0, ERROR_CASE = 1, MESSAGE_FIELD = 0 };

static MirValue text_value(Lower *cx, MirBuilder *b, const char *text) {
  const MirImm imm = {.tag = MI_STR, .a = mir_add_string(cx->module, ms_span_of_text(text))};
  return mir_b_emit(b, MOP_StrLit, NULL, 0, imm, MIR_STR);
}

static uint32_t stderr_writer(Lower *cx) {
  MirParam *params = MS_ARENA_NEW_ARRAY(&cx->module->arena, MirParam, 1);
  params[0] = (MirParam){MIR_STR, (uint8_t)MM_BORROW};
  const MirExtern def = {.name = mir_name(cx->module, ms_span_of_text("msrt_io_write_stderr")),
                         .params = params, .nparams = 1, .ret = MIR_VOID};
  return mir_extern_intern(cx->module, &def);
}

static void report(Lower *cx, MirBuilder *b, const MirAltDef *def, uint32_t alt, MirValue result, MirBlock fail) {
  mir_b_switch_to(b, fail);
  const MirTy error_ty = def->cases[ERROR_CASE].fields[0].ty;
  const MirImm cause = {.tag = MI_ALTFIELD, .a = alt, .b = ERROR_CASE, .c = 0};
  const MirValue error = mir_b_emit(b, MOP_AltGet, &result, 1, cause, error_ty);
  const MirImm field = {.tag = MI_FIELD, .a = mir_ty_data(cx->module, error_ty)->id, .b = MESSAGE_FIELD};
  const MirValue message = mir_b_emit(b, MOP_TypeGet, &error, 1, field, MIR_STR);
  const uint32_t write = stderr_writer(cx);
  const MirValue prefix = text_value(cx, b, "error: ");
  const MirValue newline = text_value(cx, b, "\n");
  (void)mir_b_call_rt(b, write, &prefix, 1);
  (void)mir_b_call_rt(b, write, &message, 1);
  (void)mir_b_call_rt(b, write, &newline, 1);
  (void)mir_b_emit(b, MOP_Drop, &result, 1, (MirImm){0}, MIR_NONE);
  mir_b_ret(b, mir_b_iconst(b, 1));
}

/* The exit status a successful Result carries: its Int payload, or its optional Int's value (0 for none), else 0. */
static MirValue success_status(Lower *cx, MirBuilder *b, const MirAltDef *def, uint32_t alt, MirValue result) {
  const MirTy payload = def->cases[OK_CASE].nfields == 0 ? MIR_VOID : def->cases[OK_CASE].fields[0].ty;
  const MirTyData *data = mir_ty_data(cx->module, payload);
  const bool is_int = payload == MIR_INT;
  if (!is_int && !(data->kind == MK_OPT && data->elem == MIR_INT)) {
    return mir_b_iconst(b, 0);
  }
  const MirImm field = {.tag = MI_ALTFIELD, .a = alt, .b = OK_CASE, .c = 0};
  const MirValue value = mir_b_emit(b, MOP_AltGet, &result, 1, field, payload);
  if (is_int) {
    return value;
  }
  const MirValue some = mir_b_emit(b, MOP_OptIsSome, &value, 1, (MirImm){0}, MIR_BOOL);
  const MirValue inner = mir_b_emit(b, MOP_OptGet, &value, 1, (MirImm){0}, MIR_INT);
  return mir_b_select(b, some, inner, mir_b_iconst(b, 0));
}

uint32_t lower_entry_status(Lower *cx, uint32_t main_func) {
  const MirFunc *main = &cx->module->funcs.ptr[main_func];
  const MirTyData *ret = mir_ty_data(cx->module, main->ret);
  const bool is_result = main->ret != MIR_VOID && ret->kind == MK_ALT && cx->module->alts.ptr[ret->id].std == MSTD_RESULT;
  if (main->nparams != 0 || (main->ret != MIR_VOID && !is_result)) {
    return main_func;
  }
  MirBuilder b;
  mir_b_init(&b, cx->module, mir_name(cx->module, ms_span_of_text("main.entry")), NULL, 0, MIR_INT);
  const MirValue result = mir_b_call(&b, main_func, NULL, 0);
  if (is_result) {
    const MirAltDef *def = &cx->module->alts.ptr[ret->id];
    const MirValue tag = mir_b_emit(&b, MOP_AltTag, &result, 1, (MirImm){0}, MIR_INT);
    const MirValue failed = mir_b_icmp(&b, MCC_EQ, tag, mir_b_iconst(&b, ERROR_CASE));
    const MirBlock fail = mir_b_new_block(&b);
    const MirBlock done = mir_b_new_block(&b);
    mir_b_br_if(&b, failed, fail, NULL, 0, done, NULL, 0);
    mir_b_seal_block(&b, fail);
    mir_b_seal_block(&b, done);
    report(cx, &b, def, ret->id, result, fail);
    mir_b_switch_to(&b, done);
    const MirValue status = success_status(cx, &b, def, ret->id, result);
    (void)mir_b_emit(&b, MOP_Drop, &result, 1, (MirImm){0}, MIR_NONE);
    mir_b_ret(&b, status);
  } else {
    mir_b_ret(&b, mir_b_iconst(&b, 0));
  }
  MirFunc built;
  if (!mir_b_into_func(&b, &built)) {
    (void)lower_fail(cx, "the entry function could not be built");
    return MIR_NONE;
  }
  return mir_add_func(cx->module, &built);
}
