/* The optimisation pipeline: which passes run, in what order, for each optimisation level. Each function's
 * rounds read the module as it was before the round and only the results are stored afterwards, so a function
 * never sees another's half-optimised body, which keeps the output independent of the order functions are
 * visited. */
#include "compiler/mir/mir_pass.h"
#include "compiler/mir/mir_print.h"
#include "compiler/mir/mir_verify.h"
#include "compiler/opt/opt_pass.h"

/* Rounds of the per-function passes. */
#define OPT_FUNCTION_ROUNDS 3

/* Re-verifies the module after `pass`; on failure writes what is wrong to `error`. */
static bool checked(const MirModule *m, bool verify, const char *pass, MsStrBuild *error) {
  if (!verify) {
    return true;
  }
  MirVerifyErrors errors = {0};
  const bool ok = mir_verify_module(m, false, &errors);
  if (!ok) {
    ms_strbuild_printf(error, "module does not verify after %s:\n", pass);
    for (size_t index = 0; index < errors.errors.len; index++) {
      mir_verify_error_text(&errors.errors.ptr[index], error);
      ms_strbuild_append_byte(error, '\n');
    }
    mir_print_module(m, error);
  }
  mir_verify_errors_free(&errors);
  return ok;
}

/* Instructions in one function above which an unoptimised build treats it as long: owned values drop at their
 * last use and the Cranelift backend allocates registers in a single pass. */
#define OPT_LONG_FUNCTION_INSTS 4000u
/* The same limit in a program that starts tasks. The unwind pass registers a cleanup for every owned value live
 * at each place that can fault or park, so values that live to scope end make a function's code and frame grow
 * with the square of its length; a frame past a task's stack slot overflows it. Dropping at the last use keeps
 * the live set, and so the growth, small. */
#define OPT_TASK_LONG_FUNCTION_INSTS 300u

static bool reads_alt_payload(const MirFunc *f) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      if (f->blocks.ptr[b].insts.ptr[i].op == MOP_AltGet) {
        return true;
      }
    }
  }
  return false;
}

/* Owned values otherwise live to scope end, and register allocation grows with the number that are live at once,
 * so only a long function pays for the earlier drops. A function that reads alternative payloads also drops
 * early, so that the payloads it copies out of a dying value can be moved (`copytakes`). */
static void lastuse_long(MirModule *m) {
  const uint32_t long_function = mir_starts_tasks(m) ? OPT_TASK_LONG_FUNCTION_INSTS : OPT_LONG_FUNCTION_INSTS;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    const MirFunc *f = &m->funcs.ptr[fi];
    if (mir_inst_count(f) > long_function || reads_alt_payload(f)) {
      (void)opt_lastuse_func(m, &m->funcs.ptr[fi]);
    }
  }
}

/* What an unoptimised build needs. A copy whose source dies right after it is a move; keeping the copies makes
 * rebuilding a value from itself, or unwrapping a nested `try` result, quadratic in the depth. */
static void unoptimised(MirModule *m) {
  (void)opt_inline_small(m);
  (void)opt_simplify_phis(m);
  (void)opt_strfuse(m);
  (void)opt_copyelim(m);
  lastuse_long(m);
  (void)opt_bytetake(m);
  (void)opt_copyelim_takes(m);
  /* After the early drops: a long function keeps the ones it moved up. */
  (void)opt_exit_drops(m);
}

/* One round of the passes that read the module but rewrite only their own function. */
static bool function_round(MirModule *m, MirFunc *f) {
  bool changed = opt_optparam_func(m, f);
  changed |= opt_simplify_func(m, f);
  changed |= opt_copyelim_func(m, f);
  changed |= opt_range_func(m, f);
  changed |= opt_ifconv_func(m, f);
  return changed;
}

/* Runs each function's rounds (at most three, stopping at the first that changes nothing) on a copy and stores
 * the copies of those that changed. */
static void function_passes(MirModule *m) {
  const uint32_t count = (uint32_t)m->funcs.len;
  MsArena arena = ms_arena_new();
  MirFunc *results = MS_ARENA_NEW_ARRAY(&arena, MirFunc, (size_t)count + 1);
  bool *changed = MS_ARENA_NEW_ARRAY(&arena, bool, (size_t)count + 1);
  for (uint32_t fi = 0; fi < count; fi++) {
    opt_func_deep_clone(m, &m->funcs.ptr[fi], &results[fi]);
    for (int round = 0; round < OPT_FUNCTION_ROUNDS; round++) {
      if (!function_round(m, &results[fi])) {
        break;
      }
      changed[fi] = true;
    }
  }
  for (uint32_t fi = 0; fi < count; fi++) {
    if (changed[fi]) {
      mir_func_release(&m->funcs.ptr[fi]);
      m->funcs.ptr[fi] = results[fi];
    } else {
      mir_func_release(&results[fi]);
    }
  }
  ms_arena_free(&arena);
}

/* One step of the pipeline: a pass or a short sequence, checked together. */
typedef struct Step {
  const char *name;
  bool (*run)(MirModule *m);
} Step;

/* The in-place append becomes an inlinable fast path, so the inliner runs again for it. */
static bool strfuse_step(MirModule *m) {
  bool changed = opt_strfuse(m);
  if (opt_appendfast(m)) {
    changed |= opt_inline(m);
  }
  return changed;
}

/* The runtime fast paths are inlinable, so the inliner runs again for them. */
static bool fastpaths_step(MirModule *m) {
  bool changed = opt_viewfast(m);
  changed |= opt_bytesfast(m);
  changed |= opt_strfast(m);
  return changed && opt_inline(m);
}

static const Step early_steps[] = {
    {"simplify", opt_simplify},
    {"copyelim", opt_copyelim},
    {"probe", opt_probe},
    {"inline", opt_inline},
    {"strfuse", strfuse_step},
    {"fastpaths", fastpaths_step},
    {"loopslot", opt_loopslot},
};

static const Step late_steps[] = {
    {"exit_drops", opt_exit_drops},
    {"reserve", opt_reserve},
    {"lastuse", opt_lastuse},
    {"bytetake", opt_bytetake},
    {"copyelim takes", opt_copyelim_takes},
    {"simplify", opt_simplify},
};

/* Runs the steps in order, stopping at the first that leaves the module unverifiable. */
static bool run_steps(MirModule *m, const Step *steps, size_t count, bool verify, MsStrBuild *error) {
  for (size_t i = 0; i < count; i++) {
    (void)steps[i].run(m);
    if (!checked(m, verify, steps[i].name, error)) {
      return false;
    }
  }
  return true;
}

bool mir_optimize(MirModule *m, MirOptLevel level, bool verify, MsStrBuild *error) {
  if (level == MIR_OPT_NONE) {
    unoptimised(m);
    return true;
  }
  if (!run_steps(m, early_steps, sizeof early_steps / sizeof early_steps[0], verify, error)) {
    return false;
  }
  /* These passes read the module but rewrite only their own function. */
  function_passes(m);
  return checked(m, verify, "function passes", error) &&
         run_steps(m, late_steps, sizeof late_steps / sizeof late_steps[0], verify, error);
}
