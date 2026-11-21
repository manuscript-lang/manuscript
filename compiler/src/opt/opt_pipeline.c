/* The optimisation pipeline: which passes run, in what order, for each optimisation level. Port of
 * `optimize` in the former Rust crates/ms-mir/src/opt/mod.rs. Each function's rounds read the module as it was
 * before the round and only the results are stored afterwards, so a function never sees another's
 * half-optimised body, which keeps the output independent of the order functions are visited. */
#include <string.h>

#include "ms/mir_pass.h"
#include "ms/mir_verify.h"
#include "opt/opt_inline.h"

/* Instructions in one function above which an unoptimised build treats it as long: owned values
 * drop at their last use and the Cranelift backend allocates registers in a single pass. */
#define OP_LONG_FUNCTION_INSTS 4000u
/* The same limit in a program that starts tasks. The unwind pass registers a cleanup for every
 * owned value live at each place that can fault or park, so values that live to scope end make a
 * function's code and frame grow with the square of its length; a frame past a task's stack slot
 * overflows it. Dropping at the last use keeps the live set, and so the growth, small. */
#define OP_TASK_LONG_FUNCTION_INSTS 300u
/* Rounds of the per-function passes. */
#define OP_FUNCTION_ROUNDS 3

/* Re-verifies the module after `pass`; on failure writes what is wrong to `error`. */
static bool op_check(const MirModule *m, bool verify, const char *pass, MsBuf *error) {
    if (!verify) {
        return true;
    }
    MirVerifyErrors errors = {0};
    if (mir_verify_module(m, false, &errors)) {
        mir_verify_errors_free(&errors);
        return true;
    }
    ms_buf_printf(error, "module does not verify after %s:\n", pass);
    for (uint32_t i = 0; i < errors.count; i++) {
        mir_verify_error_text(&errors.errors[i], error);
        ms_buf_putc(error, '\n');
    }
    mir_print_module(m, error);
    mir_verify_errors_free(&errors);
    return false;
}

static bool op_reads_alt_payload(const MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            if (f->blocks[b].insts[i].op == MOP_AltGet) {
                return true;
            }
        }
    }
    return false;
}

/* Owned values otherwise live to scope end, and register allocation grows with the number that are
 * live at once, so only a long function pays for the earlier drops. A function that reads
 * alternative payloads also drops early, so that the payloads it copies out of a dying value can
 * be moved (`copytakes`). */
static void op_lastuse_long(MirModule *m) {
    const uint32_t long_function =
        mir_starts_tasks(m) ? OP_TASK_LONG_FUNCTION_INSTS : OP_LONG_FUNCTION_INSTS;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        if (mir_inst_count(f) > long_function || op_reads_alt_payload(f)) {
            (void)mir_opt_lastuse_func(m, &m->funcs[fi]);
        }
    }
}

static void op_unoptimised(MirModule *m) {
    /* A copy whose source dies right after it is a move; keeping the copies makes rebuilding a
     * value from itself, or unwrapping a nested `try` result, quadratic in the depth. */
    (void)mir_opt_inline_small(m);
    (void)mir_opt_simplify_phis(m);
    (void)mir_opt_strfuse(m);
    (void)mir_opt_copyelim(m);
    op_lastuse_long(m);
    (void)mir_opt_bytetake(m);
    (void)mir_opt_copyelim_takes(m);
    /* After the early drops: a long function keeps the ones it moved up. */
    mir_exit_drops(m);
}

/* One round of the passes that read the module but rewrite only their own function. */
static bool op_function_round(MirModule *m, MirFunc *f) {
    bool changed = mir_opt_optparam_func(m, f);
    changed |= mir_opt_simplify_func(m, f);
    changed |= mir_opt_copyelim_func(m, f);
    changed |= mir_opt_range_func(m, f);
    changed |= mir_opt_ifconv_func(m, f);
    return changed;
}

/* Runs each function's rounds (at most three, stopping at the first that changes nothing) on a
 * copy and stores the copies of those that changed. */
static void op_function_passes(MirModule *m) {
    const uint32_t count = m->nfuncs;
    MirFunc *results = MS_NEW_N(&m->arena, MirFunc, (size_t)count + 1);
    bool *changed = MS_NEW_N(&m->arena, bool, (size_t)count + 1);
    memset(changed, 0, sizeof(bool) * count);
    for (uint32_t fi = 0; fi < count; fi++) {
        mir_func_deep_clone(m, &m->funcs[fi], &results[fi]);
        for (int round = 0; round < OP_FUNCTION_ROUNDS; round++) {
            if (!op_function_round(m, &results[fi])) {
                break;
            }
            changed[fi] = true;
        }
    }
    for (uint32_t fi = 0; fi < count; fi++) {
        if (changed[fi]) {
            m->funcs[fi] = results[fi];
        }
    }
}

/* One step of the pipeline: a pass or a short sequence, checked together. */
typedef struct OpStep {
    const char *name;
    bool (*run)(MirModule *m);
} OpStep;

/* The in-place append becomes an inlinable fast path, so the inliner runs again for it. */
static bool op_strfuse(MirModule *m) {
    bool changed = mir_opt_strfuse(m);
    if (mir_opt_appendfast(m)) {
        changed |= mir_opt_inline(m);
    }
    return changed;
}

/* The runtime fast paths are inlinable, so the inliner runs again for them. */
static bool op_fastpaths(MirModule *m) {
    bool changed = mir_opt_viewfast(m);
    changed |= mir_opt_bytesfast(m);
    changed |= mir_opt_strfast(m);
    return changed && mir_opt_inline(m);
}

static bool op_exit_drops(MirModule *m) {
    mir_exit_drops(m);
    return true;
}

static const OpStep op_early_steps[] = {
    {"simplify", mir_opt_simplify}, {"copyelim", mir_opt_copyelim}, {"probe", mir_opt_probe},
    {"inline", mir_opt_inline},     {"strfuse", op_strfuse},        {"fastpaths", op_fastpaths},        {"loopslot", mir_opt_loopslot},
};

static const OpStep op_late_steps[] = {
    {"exit_drops", op_exit_drops},  {"reserve", mir_opt_reserve},
    {"lastuse", mir_opt_lastuse},   {"bytetake", mir_opt_bytetake},
    {"copyelim takes", mir_opt_copyelim_takes}, {"simplify", mir_opt_simplify},
};

/* Runs the steps in order, stopping at the first that leaves the module unverifiable. */
static bool op_run(MirModule *m, const OpStep *steps, size_t count, bool verify, MsBuf *error) {
    for (size_t i = 0; i < count; i++) {
        (void)steps[i].run(m);
        if (!op_check(m, verify, steps[i].name, error)) {
            return false;
        }
    }
    return true;
}

bool mir_optimize(MirModule *m, MirOptLevel level, bool verify, MsBuf *error) {
    if (level == MIR_OPT_NONE) {
        op_unoptimised(m);
        return true;
    }
    if (!op_run(m, op_early_steps, sizeof op_early_steps / sizeof op_early_steps[0], verify, error)) {
        return false;
    }
    /* These passes read the module but rewrite only their own function. */
    op_function_passes(m);
    return op_check(m, verify, "function passes", error) &&
           op_run(m, op_late_steps, sizeof op_late_steps / sizeof op_late_steps[0], verify, error);
}
