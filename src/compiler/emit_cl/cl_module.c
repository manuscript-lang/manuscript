/* Owns the module driver: one Cranelift module from one MirModule, its declarations and the C `main`. */
#include "compiler/emit_cl/cl_emit.h"

#include <stdlib.h>

#include "base/alloc.h"
#include "compiler/emit/emit.h"
#include "compiler/emit_cl/cl_func.h"

/* A NUL-terminated copy of a name, in `text`. */
const char *cl_c_name(MsStrBuild *text, MsSpan name) {
  ms_strbuild_clear(text);
  ms_strbuild_append(text, name);
  ms_strbuild_append_byte(text, '\0');
  return (const char *)ms_strbuild_span(text).ptr;
}

static void add_param(ms_cl *cl, ms_cl_sig sig, ms_cl_type type) {
  ms_cl_sig_param(cl, sig, type, type == MS_CL_I8 ? MS_CL_EXT_U : MS_CL_EXT_NONE);
}

/* The signature of a MIR function: a hidden result pointer when the result has several leaves, then the leaves of each
 * argument, or one address for an argument over CL_DIRECT_BYTES. */
static ms_cl_sig function_sig(ClCx *cx, const MirFunc *func) {
  ms_cl *cl = cx->mod->cl;
  ms_cl_sig sig = ms_cl_sig_new(cl);
  MsSpan result = cl_leaves(cx, func->ret);
  if (result.len > 1) {
    add_param(cl, sig, MS_CL_I64);
  }
  for (uint32_t param = 0; param < func->nparams; param++) {
    if (cl_is_indirect(cx, func->params[param].ty)) {
      add_param(cl, sig, MS_CL_I64);
      continue;
    }
    MsSpan leaves = cl_leaves(cx, func->params[param].ty);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      add_param(cl, sig, cl_reg_type(leaves.ptr[leaf]));
    }
  }
  if (result.len == 1) {
    const ms_cl_type type = cl_reg_type(result.ptr[0]);
    ms_cl_sig_ret(cl, sig, type, type == MS_CL_I8 ? MS_CL_EXT_U : MS_CL_EXT_NONE);
  }
  return sig;
}

/* The signature a runtime function is called with: its scalar leaves, an address for what does not pass directly, a
 * trailing result pointer when the result is not a scalar. */
static ms_cl_sig extern_sig(ClCx *cx, const MirExtern *def) {
  ms_cl *cl = cx->mod->cl;
  const bool is_c = !ms_span_starts_with_text(ms_names_span(&cx->module->names, def->name), "msrt_") &&
                    !ms_span_starts_with_text(ms_names_span(&cx->module->names, def->name), "msstd_");
  ms_cl_sig sig = ms_cl_sig_new(cl);
  for (uint32_t param = 0; param < def->nparams; param++) {
    const MirTy type = def->params[param].ty;
    if (type == MIR_PTR || !mir_rt_direct(cx->module, cx->layouts, type)) {
      add_param(cl, sig, MS_CL_I64);
      continue;
    }
    MsSpan leaves = cl_leaves(cx, type);
    for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
      ms_cl_type t = cl_reg_type(leaves.ptr[leaf]);
      if (leaves.ptr[leaf] == MIR_LEAF_F32 && is_c) {
        t = MS_CL_F32;
      }
      add_param(cl, sig, t);
    }
  }
  MsSpan result = cl_leaves(cx, def->ret);
  const bool direct = mir_rt_direct(cx->module, cx->layouts, def->ret);
  const bool option = direct && mir_ty_data(cx->module, def->ret)->kind == MK_OPT && result.len == 2;
  if (!direct || option) {
    add_param(cl, sig, MS_CL_I64);
  }
  if (option) {
    ms_cl_sig_ret(cl, sig, MS_CL_I8, MS_CL_EXT_U);
  } else if (direct && result.len == 1) {
    const ms_cl_type type = cl_rt_leaf_type(result.ptr[0], is_c);
    ms_cl_sig_ret(cl, sig, type, type == MS_CL_I8 ? MS_CL_EXT_U : MS_CL_EXT_NONE);
  }
  return sig;
}

/* ---- runtime functions, declared on first use ---- */

/* A scratch context that only answers questions about types: the module-level lookups run outside any function. */
static ClCx scratch_cx(ClModule *mod) {
  ClCx cx = {0};
  cx.mod = mod;
  cx.module = mod->module;
  cx.layouts = mod->layouts;
  return cx;
}

ms_cl_func cl_extern_func(ClModule *mod, uint32_t external) {
  const MirModule *module = mod->module;
  /* The module keeps one entry per signature, so a name may be listed twice: one declaration serves both. */
  for (uint32_t earlier = 0; earlier < external; earlier++) {
    if (module->externs.ptr[earlier].name == module->externs.ptr[external].name) {
      return cl_extern_func(mod, earlier);
    }
  }
  if (!mod->extern_made[external]) {
    ClCx cx = scratch_cx(mod);
    const MirExtern *def = &module->externs.ptr[external];
    MsStrBuild text = ms_strbuild_new();
    const char *name = cl_c_name(&text, ms_names_span(&module->names, def->name));
    mod->externs[external] = ms_cl_declare_func(mod->cl, name, extern_sig(&cx, def), MS_CL_IMPORT);
    mod->extern_made[external] = true;
    ms_strbuild_free(&text);
  }
  return mod->externs[external];
}

ms_cl_func cl_runtime_func(ClModule *mod, const char *name, uint32_t nargs, bool has_result) {
  const MirModule *module = mod->module;
  const MsSpan wanted = ms_span_of_text(name);
  for (uint32_t index = 0; index < module->externs.len; index++) {
    if (ms_span_equal(ms_names_span(&module->names, module->externs.ptr[index].name), wanted)) {
      return cl_extern_func(mod, index);
    }
  }
  for (uint32_t index = 0; index < mod->nnamed; index++) {
    if (mod->named[index].name == name) {
      return mod->named[index].func;
    }
  }
  ms_cl_sig sig = ms_cl_sig_new(mod->cl);
  for (uint32_t arg = 0; arg < nargs; arg++) {
    ms_cl_sig_param(mod->cl, sig, MS_CL_I64, MS_CL_EXT_NONE);
  }
  if (has_result) {
    ms_cl_sig_ret(mod->cl, sig, MS_CL_I64, MS_CL_EXT_NONE);
  }
  const ms_cl_func func = ms_cl_declare_func(mod->cl, name, sig, MS_CL_IMPORT);
  mod->named[mod->nnamed++] = (struct ClNamed){name, func};
  return func;
}

ms_cl_func cl_post_func(ClModule *mod, ClPost post) {
  static const struct {
    const char *name;
    uint32_t nargs;
  } posts[CL_POST_COUNT] = {
      [CL_POST_INT_OVERFLOW] = {"msrt_post_int_overflow", 0}, [CL_POST_INT_RANGE] = {"msrt_post_int_range", 0},
      [CL_POST_DIV_ZERO] = {"msrt_post_div_zero", 0},         [CL_POST_REM_ZERO] = {"msrt_post_rem_zero", 0},
      [CL_POST_DIV_OVERFLOW] = {"msrt_post_div_overflow", 2}, [CL_POST_INDEX] = {"msrt_post_index", 2},
      [CL_POST_UNWRAP_NONE] = {"msrt_post_unwrap_none", 0},   [CL_POST_FAULT_POSTED] = {"msrt_fault_posted", 0},
  };
  return cl_runtime_func(mod, posts[post].name, posts[post].nargs, false);
}

/* ---- the C `main` ---- */

/* `int main(int argc, char **argv)`: hands the entry function and the tables to the runtime (`msrt_start`). */
static void define_main(ClModule *mod, ms_cl_fn *fb, const ms_cl_data *tables) {
  ms_cl *cl = mod->cl;
  ms_cl_sig main_sig = ms_cl_sig_new(cl);
  ms_cl_sig_param(cl, main_sig, MS_CL_I32, MS_CL_EXT_NONE);
  ms_cl_sig_param(cl, main_sig, MS_CL_I64, MS_CL_EXT_NONE);
  ms_cl_sig_ret(cl, main_sig, MS_CL_I32, MS_CL_EXT_NONE);
  ms_cl_sig start_sig = ms_cl_sig_new(cl);
  ms_cl_sig_param(cl, start_sig, MS_CL_I64, MS_CL_EXT_NONE);
  ms_cl_sig_param(cl, start_sig, MS_CL_I64, MS_CL_EXT_NONE);
  ms_cl_sig_param(cl, start_sig, MS_CL_I32, MS_CL_EXT_NONE);
  ms_cl_sig_param(cl, start_sig, MS_CL_I64, MS_CL_EXT_NONE);
  ms_cl_sig_ret(cl, start_sig, MS_CL_I32, MS_CL_EXT_NONE);
  const ms_cl_func main_func = ms_cl_declare_func(cl, "main", main_sig, MS_CL_EXPORT);
  const ms_cl_func start = ms_cl_declare_func(cl, "msrt_start", start_sig, MS_CL_IMPORT);
  ms_cl_fn_begin(fb, main_func);
  const ms_cl_block entry = ms_cl_entry(fb);
  ms_cl_val entry_address = ms_cl_func_addr(fb, mod->funcs[mod->module->entry]);
  ms_cl_val tables_address = tables != NULL ? ms_cl_data_addr(fb, *tables) : ms_cl_i64const(fb, 0);
  ms_cl_val result = ms_cl_call1(fb, start,
                                 (ms_cl_val[]){entry_address, tables_address, ms_cl_block_param(fb, entry, 0),
                                               ms_cl_block_param(fb, entry, 1)}, 4);
  ms_cl_ret1(fb, result);
  ms_cl_seal_all(fb);
  ms_cl_fn_end(fb);
}

/* ---- the module ---- */

bool cl_emit_module(const MirModule *module, const MirData *data, const MirGlue *glue, const ClOptions *options,
                    MsStrBuild *object, MsStrBuild *why) {
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  ClModule mod = {0};
  mod.module = module;
  mod.data = data;
  mod.glue = glue;
  mod.layouts = &layouts;
  /* MS_CL_THREADS overrides the library's one worker per core (1 compiles on the calling thread). */
  const char *threads = getenv("MS_CL_THREADS");
  const char *const keys[] = {"ms_threads"};
  mod.cl = ms_cl_new(NULL, threads != NULL ? 1 : 0, keys, &threads);
  if (mod.cl == NULL) {
    ms_strbuild_append_text(why, "Cranelift: ");
    ms_strbuild_append_text(why, ms_cl_error(NULL));
    mir_layouts_free(&layouts);
    return false;
  }
  const uint32_t nfuncs = (uint32_t)module->funcs.len;
  mod.funcs = ms_alloc((nfuncs + 1) * sizeof(ms_cl_func));
  mod.externs = ms_alloc_zeroed((module->externs.len + 1) * sizeof(ms_cl_func));
  mod.extern_made = ms_alloc_zeroed(module->externs.len + 1);
  uint32_t *scope_base = ms_alloc((nfuncs + 1) * sizeof(uint32_t));
  uint32_t total_scopes = 0;
  for (uint32_t index = 0; index < nfuncs; index++) {
    scope_base[index] = total_scopes;
    total_scopes += (uint32_t)module->funcs.ptr[index].scopes.len;
  }
  ClCx cx = scratch_cx(&mod);
  MsStrBuild text = ms_strbuild_new();
  for (uint32_t index = 0; index < nfuncs; index++) {
    const MirFunc *func = &module->funcs.ptr[index];
    const bool exported = options->export_all || func->linkage == ML_EXPORT || module->entry == index;
    cx.func = func;
    mod.funcs[index] = ms_cl_declare_func(mod.cl, cl_c_name(&text, ms_names_span(&module->names, func->name)),
                                          function_sig(&cx, func), exported ? MS_CL_EXPORT : MS_CL_LOCAL);
  }
  cl_define_data(&mod);
  if (options->places) {
    for (uint32_t file = 0; file < module->files.len; file++) {
      ms_cl_dwarf_file(mod.cl, file, cl_c_name(&text, module->files.ptr[file]));
    }
  }
  ms_cl_data tables_data = {0};
  if (options->tables != NULL) {
    tables_data = ms_cl_declare_data(mod.cl, "ms_tables", MS_CL_EXPORT, 0, 0);
  }
  bool ok = true;
  ms_cl_fn *fb = ms_cl_fn_new(mod.cl);
  cx.fb = fb;
  cx.places = options->places;
  for (uint32_t index = 0; index < nfuncs; index++) {
    cx.func = &module->funcs.ptr[index];
    cx.index = index;
    cx.why = NULL;
    cx.scope_base = scope_base[index];
    cx.body_scope = total_scopes + index + 1;
    if (cl_lower_function(&cx)) {
      continue;
    }
    ms_strbuild_append(why, ms_names_span(&module->names, cx.func->name));
    ms_strbuild_printf(why, ": %s\n", cx.why != NULL ? cx.why : ms_cl_fn_error(fb));
    ok = false;
  }
  if (ok && module->entry != MIR_NONE) {
    define_main(&mod, fb, options->tables != NULL ? &tables_data : NULL);
  }
  ms_cl_fn_free(fb);
  if (ok && options->tables != NULL) {
    ok = cl_define_tables(&mod, options->tables, tables_data, why);
  }
  if (ok) {
    size_t size = 0;
    const uint8_t *bytes = ms_cl_finish(mod.cl, &size);
    if (bytes == NULL) {
      ms_strbuild_printf(why, "Cranelift: %s\n", ms_cl_error(mod.cl));
      ok = false;
    } else {
      ms_strbuild_append(object, ms_span_of(bytes, size));
    }
  }
  cl_free_data(&mod);
  ms_cl_free(mod.cl);
  ms_strbuild_free(&text);
  ms_free(scope_base);
  ms_free(mod.funcs);
  ms_free(mod.externs);
  ms_free(mod.extern_made);
  mir_layouts_free(&layouts);
  return ok;
}
