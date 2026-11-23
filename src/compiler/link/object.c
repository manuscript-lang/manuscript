/* Owns the object step: write the IR, optimize it with `opt`, and have `llc` write the object (see object.h). */
#include "compiler/link/object.h"

#include "base/file.h"
#include "base/path.h"
#include "base/process.h"
#include "base/bytes.h"
#include "compiler/emit/emit.h"
#include "compiler/link/asm_tables.h"

/* Runs `argv` with its output in `log`; on failure `why` names `what` and holds the output. */
static bool run_tool(MsSpan what, const MsSpan *argv, size_t argc, MsSpan log, MsStrBuild *why) {
  MsProcessSpec spec = {.argv = argv, .argc = argc, .directory = ms_span_of(NULL, 0), .log_path = log};
  return ms_process_run_logged(what, &spec, why);
}

static MsString in_directory(MsSpan directory, const char *name) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, directory, ms_span_of_text(name));
  return ms_strbuild_finish(&path);
}

/* `opt` over `input`, writing the bitcode to `bitcode`. */
static bool optimize(const ObjectOptions *options, MsSpan triple_flag, MsSpan input, MsSpan bitcode, MsSpan log,
                     MsStrBuild *why) {
  MsSpan argv[10];
  size_t argc = 0;
  argv[argc++] = options->opt;
  if (!options->vectorize) {
    argv[argc++] = ms_span_of_text("-vectorize-loops=false");
    argv[argc++] = ms_span_of_text("-vectorize-slp=false");
  }
  if (options->verify) {
    argv[argc++] = ms_span_of_text("-verify-each");
  }
  argv[argc++] = triple_flag;
  argv[argc++] = ms_span_of_text(options->debug ? "-passes=default<O2>" : "-passes=default<O3>");
  argv[argc++] = input;
  argv[argc++] = ms_span_of_text("-o");
  argv[argc++] = bitcode;
  return run_tool(ms_span_of_text("opt (LLVM optimizer)"), argv, argc, log, why);
}

/* `llc` over `input`, writing the object. */
static bool generate(const ObjectOptions *options, MsSpan triple_flag, MsSpan input, MsSpan object, MsSpan log,
                     const char *filetype, MsStrBuild *why) {
  MsSpan argv[12];
  size_t argc = 0;
  argv[argc++] = options->llc;
  argv[argc++] = ms_span_of_text(options->speed ? (options->debug ? "-O2" : "-O3") : "-O0");
  argv[argc++] = ms_span_of_text(filetype);
  argv[argc++] = ms_span_of_text("-relocation-model=pic");
  argv[argc++] = triple_flag;
#if defined(__x86_64__)
  argv[argc++] = ms_span_of_text("-align-loops=32");
  argv[argc++] = ms_span_of_text("-mcpu=x86-64");
#endif
  argv[argc++] = input;
  argv[argc++] = ms_span_of_text("-o");
  argv[argc++] = object;
  return run_tool(ms_span_of_text("llc (LLVM code generator)"), argv, argc, log, why);
}

/* The assembly `text` as an IR module of `module asm` lines, which `llc` assembles into the object. */
static void wrap_assembly(MsSpan triple, MsSpan text, MsStrBuild *ir) {
  ms_strbuild_append_text(ir, "target triple = \"");
  ms_strbuild_append(ir, triple);
  ms_strbuild_append_text(ir, "\"\n");
  size_t start = 0;
  while (start < text.len) {
    size_t end = start;
    while (end < text.len && text.ptr[end] != '\n') {
      end++;
    }
    ms_strbuild_append_text(ir, "module asm \"");
    for (size_t at = start; at < end; at++) {
      uint8_t byte = text.ptr[at];
      if (byte >= 0x20 && byte < 0x7f && byte != '"' && byte != '\\') {
        ms_strbuild_append_byte(ir, byte);
        continue;
      }
      ms_strbuild_append_byte(ir, '\\');
      if (byte < 16) {
        ms_strbuild_append_byte(ir, '0');
      }
      ms_strbuild_append_u64_radix(ir, byte, 16);
    }
    ms_strbuild_append_text(ir, "\"\n");
    start = end + 1;
  }
}

/* The object of a program with fault tables: `llc` writes the assembly, the tables are added to it, and `llc`
 * assembles the result. */
static bool tables_object(const ObjectOptions *options, MsSpan triple_flag, MsSpan input, MsSpan object, MsSpan log,
                          MsStrBuild *why) {
  MsString assembly_path = in_directory(options->directory, "program.s");
  MsString wrapped_path = in_directory(options->directory, "tables.ll");
  bool ok = generate(options, triple_flag, input, ms_string_span(&assembly_path), log,
                     "-filetype=asm", why);
  MsBytes assembly = {0};
  ok = ok && ms_file_read(ms_string_span(&assembly_path), &assembly);
  MsArena arena = ms_arena_new();
  MsStrBuild text = ms_strbuild_new();
  MsStrBuild ir = ms_strbuild_new();
  ok = ok && link_asm_tables(&arena, options->module, options->tables, ms_bytes_span(&assembly), &text, why);
  if (ok) {
    wrap_assembly(ms_span_of(triple_flag.ptr + 9, triple_flag.len - 9), ms_strbuild_span(&text), &ir);
    ok = ms_file_write(ms_string_span(&wrapped_path), ms_strbuild_span(&ir));
  }
  ObjectOptions plain = *options;
  plain.speed = false;
  ok = ok && generate(&plain, triple_flag, ms_string_span(&wrapped_path), object, log, "-filetype=obj", why);
  ms_path_remove(ms_string_span(&assembly_path));
  ms_path_remove(ms_string_span(&wrapped_path));
  ms_strbuild_free(&ir);
  ms_strbuild_free(&text);
  ms_bytes_free(&assembly);
  ms_arena_free(&arena);
  ms_string_release(&assembly_path);
  ms_string_release(&wrapped_path);
  return ok;
}

bool link_make_object(const ObjectOptions *options, MsSpan ir, MsSpan object, MsStrBuild *why) {
  MsSpan triple = emit_host_triple();
  if (triple.len == 0) {
    ms_strbuild_append_text(why, "native builds are not supported on this host");
    return false;
  }
  MsStrBuild flag = ms_strbuild_new();
  ms_strbuild_append_text(&flag, "-mtriple=");
  ms_strbuild_append(&flag, triple);
  MsString triple_flag = ms_strbuild_finish(&flag);
  MsString text = in_directory(options->directory, "program.ll");
  MsString bitcode = in_directory(options->directory, "program.bc");
  MsString log = in_directory(options->directory, "tool.log");
  bool ok = ms_file_write(ms_string_span(&text), ir);
  if (!ok) {
    ms_strbuild_append_text(why, "cannot write ");
    ms_strbuild_append(why, ms_string_span(&text));
  }
  MsSpan input = ms_string_span(&text);
  if (ok && options->speed) {
    ok = optimize(options, ms_string_span(&triple_flag), input, ms_string_span(&bitcode), ms_string_span(&log), why);
    input = ms_string_span(&bitcode);
  }
  if (ok && options->tables != NULL) {
    ok = tables_object(options, ms_string_span(&triple_flag), input, object, ms_string_span(&log), why);
  } else {
    ok = ok && generate(options, ms_string_span(&triple_flag), input, object, ms_string_span(&log),
                        "-filetype=obj", why);
  }
  ms_path_remove(ms_string_span(&text));
  ms_path_remove(ms_string_span(&bitcode));
  ms_path_remove(ms_string_span(&log));
  ms_string_release(&text);
  ms_string_release(&bitcode);
  ms_string_release(&log);
  ms_string_release(&triple_flag);
  return ok;
}
