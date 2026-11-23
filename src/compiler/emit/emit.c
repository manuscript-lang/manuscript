/* Owns the module driver: one LLVM module from one MirModule. */
#include "compiler/emit/emit.h"

#include "compiler/emit/emit_debug.h"
#include "compiler/emit/emit_decl.h"
#include "compiler/emit/emit_hints.h"
#include "compiler/emit/emit_func.h"

/* The LLVM target triple of the machine the emitter runs on, which is the one the program is built for.
 * Without it a tool that reads the IR alone (`opt`) assumes a generic layout and sizes loops differently from
 * the compiler. Windows executables link over the mingw-w64 CRT. */
#if defined(__x86_64__) || defined(_M_X64)
#define EMIT_ARCH "x86_64"
#elif defined(__aarch64__) || defined(_M_ARM64)
#define EMIT_ARCH "aarch64"
#endif

#if defined(EMIT_ARCH) && defined(__linux__)
#define EMIT_TRIPLE EMIT_ARCH "-unknown-linux-gnu"
#elif defined(EMIT_ARCH) && defined(__APPLE__)
#define EMIT_TRIPLE EMIT_ARCH "-apple-darwin"
#elif defined(EMIT_ARCH) && defined(_WIN32)
#define EMIT_TRIPLE EMIT_ARCH "-w64-windows-gnu"
#endif

/* The metadata the list element accesses refer to: a root, the scalar element type and its access tag. */
#define EMIT_TBAA_ROOT 900000
#define EMIT_TBAA_SCALAR 900001
#define EMIT_TBAA_SCALAR_TAG 900002

static void write_tbaa(MsStrBuild *out) {
  ms_strbuild_printf(out,
                     "!%d = !{!\"ms.tbaa\"}\n!%d = !{!\"ms.scalar-elem\", !%d, i64 0}\n!%d = !{!%d, !%d, i64 0}\n",
                     EMIT_TBAA_ROOT, EMIT_TBAA_SCALAR, EMIT_TBAA_ROOT, EMIT_TBAA_SCALAR_TAG, EMIT_TBAA_SCALAR,
                     EMIT_TBAA_SCALAR);
}

/* The file name the compile unit shows: the base name of the first function's file. */
static MsSpan source_name(const MirModule *module) {
  for (uint32_t index = 0; index < module->funcs.len; index++) {
    uint32_t file = module->funcs.ptr[index].loc.file;
    if (file >= module->files.len) {
      continue;
    }
    MsSpan name = module->files.ptr[file];
    for (size_t at = name.len; at > 0; at--) {
      if (name.ptr[at - 1] == '/' || name.ptr[at - 1] == '\\') {
        return ms_span_of(name.ptr + at, name.len - at);
      }
    }
    return name;
  }
  return ms_span_of_text("ms");
}

MsSpan emit_host_triple(void) {
#ifdef EMIT_TRIPLE
  return ms_span_of_text(EMIT_TRIPLE);
#else
  return ms_span_of(NULL, 0);
#endif
}

bool emit_module(const MirModule *module, const MirData *data, const MirGlue *glue, const EmitOptions *options, MsStrBuild *out, MsStrBuild *why) {
#ifdef EMIT_TRIPLE
  ms_strbuild_printf(out, "target triple = \"%s\"\n", EMIT_TRIPLE);
#endif
  MirLayouts layouts;
  mir_layouts_init(&layouts, module);
  EmitCx cx = {0};
  cx.module = module;
  cx.out = out;
  cx.layouts = &layouts;
  cx.data = data;
  cx.glue = glue;
  cx.export_all = options->export_all;
  cx.wide_leaves = options->wide_leaves;
  EmitDebug debug;
  uint32_t total_scopes = 0;
  for (uint32_t index = 0; index < module->funcs.len; index++) {
    total_scopes += (uint32_t)module->funcs.ptr[index].scopes.len;
  }
  if (options->places) {
    emit_debug_init(&debug);
    cx.debug = &debug;
  }
  EmitHints hints;
  emit_hints_init(&hints, module, glue);
  uint32_t scope_base = 0;
  bool ok = true;
  for (uint32_t index = 0; index < module->funcs.len; index++) {
    cx.func = &module->funcs.ptr[index];
    cx.why = NULL;
    cx.next = 0;
    cx.body_line = 0;
    cx.scope_base = scope_base;
    cx.body_scope = total_scopes + index + 1;
    cx.noinline = emit_hint_deep_glue(&cx, &hints, index);
    cx.pure = emit_hint_pure(&cx, &hints, index);
    scope_base += (uint32_t)cx.func->scopes.len;
    if (emit_function(&cx, index)) {
      continue;
    }
    ms_strbuild_append(why, ms_names_span(&module->names, cx.func->name));
    ms_strbuild_printf(why, ": %s\n", cx.why != NULL ? cx.why : "unsupported");
    ok = false;
  }
  emit_hints_free(&hints);
  cx.func = NULL;
  emit_define_data(&cx);
  emit_declarations(&cx);
  mir_layouts_free(&layouts);
  write_tbaa(out);
  if (options->places) {
    emit_debug_finish(&cx, source_name(module));
    emit_debug_free(&debug);
  }
  return ok;
}
