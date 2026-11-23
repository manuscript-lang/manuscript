/* The optimisation pipeline: which passes run, and in what order. Every build type runs it. Each function's
 * rounds read the module as it was before the round and only the results are stored afterwards, so a function
 * never sees another's half-optimised body, which keeps the output independent of the order functions are
 * visited. */
#include "compiler/mir/mir_pass.h"
#include "compiler/mir/mir_verify.h"
#include "compiler/opt/opt_inline.h"
#include "compiler/opt/opt_pass.h"

/* Rounds of the per-function passes. */
#define OPT_FUNCTION_ROUNDS 3

/* One round of the passes that read the module but rewrite only their own function. */
static bool function_round(MirModule *m, MirFunc *f) {
  bool changed = opt_optparam_func(m, f);
  changed |= opt_simplify_func(m, f);
  changed |= opt_copyelim_func(m, f);
  changed |= opt_range_func(m, f);
  changed |= opt_ifconv_func(m, f);
  changed |= opt_twins_func(m, f);
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

/* One step of the pipeline: a pass or a short sequence. */
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

/* Fused loops leave dead values and merge blocks, so the simplifier cleans up after them. */
static bool opt_fuse_step(MirModule *m) {
  bool changed = false;
  while (opt_fuse(m)) {
    changed = true;
    (void)opt_simplify(m);
  }
  return changed;
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
    {"fuse", opt_fuse_step},
    {"fieldview", opt_fieldview},
    {"exit_drops", opt_exit_drops},
    {"reserve", opt_reserve},
    {"lastuse", opt_lastuse},
    {"bytetake", opt_bytetake},
    {"copyelim takes", opt_copyelim_takes},
    {"simplify", opt_simplify},
};

static void run_steps(MirModule *m, const Step *steps, size_t count) {
  for (size_t i = 0; i < count; i++) {
    (void)steps[i].run(m);
  }
}

bool mir_optimize(MirModule *m, bool compact, bool verify, MsStrBuild *error) {
  m->inline_base = compact ? OPT_INLINE_COMPACT_THRESHOLD : OPT_INLINE_BASE_THRESHOLD;
  run_steps(m, early_steps, sizeof early_steps / sizeof early_steps[0]);
  /* These passes read the module but rewrite only their own function. */
  function_passes(m);
  run_steps(m, late_steps, sizeof late_steps / sizeof late_steps[0]);
  if (!verify) {
    return true;
  }
  MirVerifyErrors errors = {0};
  const bool ok = mir_verify_module(m, false, &errors);
  if (!ok) {
    ms_strbuild_append_text(error, "module does not verify after optimising:\n");
    for (size_t index = 0; index < errors.errors.len; index++) {
      mir_verify_error_text(&errors.errors.ptr[index], error);
      ms_strbuild_append_byte(error, '\n');
    }
  }
  mir_verify_errors_free(&errors);
  return ok;
}
