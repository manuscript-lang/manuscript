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

/* What an unoptimised build needs. */
static void unoptimised(MirModule *m) {
  (void)opt_simplify_phis(m);
  (void)opt_strfuse(m);
  (void)opt_bytetake(m);
}

/* One round of the passes that read the module but rewrite only their own function. */
static bool function_round(MirModule *m, MirFunc *f) {
  return opt_simplify_func(m, f);
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

static const Step early_steps[] = {
    {"simplify", opt_simplify},
    {"strfuse", opt_strfuse},
};

static const Step late_steps[] = {
    {"bytetake", opt_bytetake},
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
