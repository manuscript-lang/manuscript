/* The program's entry (`MirModule.entry`): the exported function the runtime calls. A `main` that
 * returns `Int` is the entry itself. Any other `main` gets a wrapper named `main.1`, as the Rust
 * lowering makes it: it calls `main`, exits 0 after a Void, and for a `Result` prints
 * `error: MESSAGE` on standard error and exits 1 on a failure, else exits with the `Int?` payload
 * when there is one. The wrapper has no source positions: no line of the program is its own. */
#include "ms/lower_internal.h"
#include "ms/mir_analysis.h"

/* `text` written to standard error. */
static void le_write_literal(Lb *lb, uint32_t write, const char *text) {
    const MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, text, strlen(text))};
    const MirValue lit = mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, imm, MIR_STR);
    (void)mir_b_call_rt(&lb->b, write, &lit, 1);
}

/* The block a failed `result` reaches: reports the error's message and exits 1. False when the
 * error case does not hold a record whose first field is the message. */
static bool le_report_failure(Lb *lb, MirValue result, uint32_t alt) {
    const MirCaseDef *failure = &lb->m->alts[alt].cases[LA_ERROR];
    const MirTyData *error = failure->nfields == 1 ? mir_ty_data(lb->m, failure->fields[0].ty) : NULL;
    if (error == NULL || error->kind != MK_TYPE || lb->m->type_defs[error->id].nfields == 0 ||
        lb->m->type_defs[error->id].fields[0].ty != MIR_STR) {
        return false;
    }
    const MirImm cause = {.tag = MI_ALTFIELD, .a = alt, .b = LA_ERROR, .c = 0};
    const MirValue payload = mir_b_emit(&lb->b, MOP_AltGet, &result, 1, cause, failure->fields[0].ty);
    const MirImm first = {.tag = MI_FIELD, .a = error->id, .b = 0};
    const MirValue message = mir_b_emit(&lb->b, MOP_TypeGet, &payload, 1, first, MIR_STR);
    const MirTy text = MIR_STR;
    const uint32_t write = lb_runtime_extern(lb, "msrt_io_write_stderr", &text, 1, MIR_VOID, MR_NONE, false);
    le_write_literal(lb, write, "error: ");
    (void)mir_b_call_rt(&lb->b, write, &message, 1);
    le_write_literal(lb, write, "\n");
    (void)mir_b_emit(&lb->b, MOP_Drop, &result, 1, (MirImm){0}, MIR_NONE);
    mir_b_ret(&lb->b, mir_b_iconst(&lb->b, 1));
    return true;
}

/* The block a successful `result` reaches: exits with the number an `Int?` payload holds, else 0. */
static void le_exit_success(Lb *lb, MirValue result, uint32_t alt) {
    const MirCaseDef *success = &lb->m->alts[alt].cases[LA_OK];
    const MirImm value = {.tag = MI_ALTFIELD, .a = alt, .b = LA_OK, .c = 0};
    const MirValue payload = mir_b_emit(&lb->b, MOP_AltGet, &result, 1, value, success->fields[0].ty);
    const MirTyData *held = mir_ty_data(lb->m, success->fields[0].ty);
    MirValue status;
    if (held->kind == MK_OPT) {
        const MirValue present = mir_b_emit(&lb->b, MOP_OptIsSome, &payload, 1, (MirImm){0}, MIR_BOOL);
        const MirValue number = mir_b_emit(&lb->b, MOP_OptGet, &payload, 1, (MirImm){0}, held->elem);
        status = mir_b_select(&lb->b, present, number, mir_b_iconst(&lb->b, 0));
    } else {
        status = mir_b_iconst(&lb->b, 0);
    }
    (void)mir_b_emit(&lb->b, MOP_Drop, &result, 1, (MirImm){0}, MIR_NONE);
    mir_b_ret(&lb->b, status);
}

/* The wrapper around `user`, a `main` that does not return `Int`; MIR_NONE when its result is none
 * a `main` may have. */
static uint32_t le_wrapper(Lb *lb, uint32_t user) {
    const MirTy ret = lb->m->funcs[user].ret;
    const MirTyData *shape = mir_ty_data(lb->m, ret);
    const bool is_result = shape->kind == MK_ALT && lb->m->alts[shape->id].std == MSTD_RESULT &&
                           lb->m->alts[shape->id].cases[LA_OK].nfields == 1;
    if (ret != MIR_VOID && !is_result) {
        return MIR_NONE;
    }
    mir_b_init(&lb->b, lb->m, mir_name(lb->m, "main.1", 6), NULL, 0, MIR_INT);
    const MirValue result = mir_b_call(&lb->b, user, NULL, 0);
    bool built = true;
    if (!is_result) {
        mir_b_ret(&lb->b, mir_b_iconst(&lb->b, 0));
    } else {
        const MirValue tag = mir_b_emit(&lb->b, MOP_AltTag, &result, 1, (MirImm){0}, MIR_INT);
        const MirValue failed = mir_b_icmp(&lb->b, MCC_EQ, tag, mir_b_iconst(&lb->b, LA_ERROR));
        const MirBlock bad = mir_b_new_block(&lb->b);
        const MirBlock good = mir_b_new_block(&lb->b);
        mir_b_br_if(&lb->b, failed, bad, NULL, 0, good, NULL, 0);
        mir_b_seal_block(&lb->b, bad);
        mir_b_seal_block(&lb->b, good);
        mir_b_switch_to(&lb->b, bad);
        built = le_report_failure(lb, result, shape->id);
        mir_b_switch_to(&lb->b, good);
        le_exit_success(lb, result, shape->id);
    }
    mir_func_compact_blocks(&lb->b.f);
    lb->b.f.linkage = ML_EXPORT;
    MirFunc wrapper = {0};
    // Finishing also frees the builder's scratch tables, which a refused wrapper needs too.
    return mir_b_into_func(&lb->b, &wrapper) && built ? mir_add_func(lb->m, &wrapper) : MIR_NONE;
}

void lb_set_entry(Lb *lb, uint32_t user) {
    lb->m->entry = lb->m->funcs[user].ret == MIR_INT ? user : le_wrapper(lb, user);
}
