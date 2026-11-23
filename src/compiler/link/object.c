/* Owns the object step: write the IR, optimize it with `opt`, and have `llc` write the object (see object.h). */
#include "compiler/link/object.h"

#include "base/file.h"
#include "base/path.h"
#include "base/process.h"
#include "base/bytes.h"
#include "compiler/emit/emit.h"
#include "compiler/link/asm_tables.h"
#include "compiler/link/llvm_inproc.h"

/* Runs `argv` with its output in `log`; on failure `why` names `what` and holds the output. */
static bool run_tool(MsSpan what, const MsSpan *argv, size_t argc, MsSpan log, MsStrBuild *why) {
  MsProcessSpec spec = {.argv = argv, .argc = argc, .directory = ms_span_of(NULL, 0), .log_path = log};
  return ms_process_run_logged(what, &spec, why);
}

/* The scratch file `<stem><extension>` of this module in the options' directory; with several modules the stem
 * carries the module's number so they do not overwrite one another. */
static MsString scratch_file(const ObjectOptions *options, const char *stem, const char *extension) {
  MsStrBuild name = ms_strbuild_new();
  ms_strbuild_append_text(&name, stem);
  if (options->units > 1) {
    ms_strbuild_printf(&name, ".%u", options->unit);
  }
  ms_strbuild_append_text(&name, extension);
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, options->directory, ms_strbuild_span(&name));
  ms_strbuild_free(&name);
  return ms_strbuild_finish(&path);
}

/* A Debug build optimizes lightly: SROA, early CSE, instruction combining and CFG simplification keep frames as small
 * as `default<O2>` does (measured on a 30 MB program: 0.2% apart) for about a fifth of the optimizer's time; `llc`
 * pairs it with -O1, the basic register allocator and no machine scheduler, which cost no frame size. FastISel is
 * not used: it changes the line a fault trace reports. */
static const char debug_pipeline[] = "-passes=function(sroa,early-cse,simplifycfg,instcombine<no-verify-fixpoint>,sroa,simplifycfg)";

/* DSE's default memory-walk limit makes one huge generated function (60k lines in the YAML parser) cost 4 s of a
 * 15 s optimizer run; 10 takes 15% off the module's optimizer time and leaves the suite's binaries unchanged. */
#define DSE_WALK_LIMIT "-dse-memoryssa-walklimit=10"

/* `opt` over `input`, writing the bitcode to `bitcode`. */
static bool optimize(const ObjectOptions *options, MsSpan triple_flag, MsSpan input, MsSpan bitcode, MsSpan log,
                     MsStrBuild *why) {
  MsSpan argv[14];
  size_t argc = 0;
  argv[argc++] = options->opt;
  if (!options->vectorize) {
    argv[argc++] = ms_span_of_text("-vectorize-loops=false");
    argv[argc++] = ms_span_of_text("-vectorize-slp=false");
  }
  /* Dead-store elimination walks the memory defs of a block; on a function of thousands of statements, one block of
   * tens of thousands of stores and calls, that was half of `opt`'s time (html: 6.9 s of 12.8 s) and removed one line
   * of 239000 more than the limits do. */
  argv[argc++] = ms_span_of_text("-dse-memoryssa-defs-per-block-limit=500");
  argv[argc++] = ms_span_of_text("-dse-memoryssa-walklimit=20");
  argv[argc++] = ms_span_of_text("-dse-memoryssa-scanlimit=50");
  if (options->verify) {
    argv[argc++] = ms_span_of_text("-verify-each");
  }
  argv[argc++] = ms_span_of_text(DSE_WALK_LIMIT);
  argv[argc++] = triple_flag;
  argv[argc++] = ms_span_of_text(options->debug ? debug_pipeline : "-passes=default<O3>");
  argv[argc++] = input;
  argv[argc++] = ms_span_of_text("-o");
  argv[argc++] = bitcode;
  return run_tool(ms_span_of_text("opt (LLVM optimizer)"), argv, argc, log, why);
}

/* `llc` over `input`, writing the object. */
static bool generate(const ObjectOptions *options, MsSpan triple_flag, MsSpan input, MsSpan object, MsSpan log,
                     const char *filetype, MsStrBuild *why) {
  MsSpan argv[14];
  size_t argc = 0;
  argv[argc++] = options->llc;
  argv[argc++] = ms_span_of_text(options->speed ? (options->debug ? "-O1" : "-O3") : "-O0");
  if (options->debug && options->speed) {
    argv[argc++] = ms_span_of_text("-regalloc=basic");
    argv[argc++] = ms_span_of_text("-enable-misched=0");
  }
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
        const size_t run = at;
        while (at + 1 < end && text.ptr[at + 1] >= 0x20 && text.ptr[at + 1] < 0x7f && text.ptr[at + 1] != '"' &&
               text.ptr[at + 1] != '\\') {
          at++;
        }
        ms_strbuild_append(ir, ms_span_of(text.ptr + run, at + 1 - run));
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

/* Phase two with fault tables, from the child processes' assembly: the tables are added to it and `llc` assembles the
 * result. */
static bool tables_object(const ObjectOptions *options, MsSpan triple_flag, MsSpan object, MsSpan log, MsStrBuild *why) {
  MsString assembly_path = scratch_file(options, "program", ".s");
  MsString wrapped_path = scratch_file(options, "tables", ".ll");
  MsBytes assembly = {0};
  bool ok = ms_file_read(ms_string_span(&assembly_path), &assembly);
  MsArena arena = ms_arena_new();
  MsStrBuild text = ms_strbuild_new();
  MsStrBuild ir = ms_strbuild_new();
  ok = ok && link_asm_tables(&arena, options->module, options->tables, ms_bytes_span(&assembly), options->unit,
                             options->units, &text, why);
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

static LlvmBuffer buffer_of(const ObjectCode *code) {
  return (LlvmBuffer){.data = code->data, .size = code->size, .handle = code->handle};
}

void link_discard(ObjectCode *code) {
  LlvmBuffer buffer = buffer_of(code);
  llvm_buffer_free(&buffer);
  *code = (ObjectCode){0};
}

static bool write_object(MsSpan object, const LlvmBuffer *buffer, MsStrBuild *why) {
  return ms_file_write(object, ms_span_of((const uint8_t *)buffer->data, buffer->size)) ||
         (ms_strbuild_append_text(why, "cannot write the object"), false);
}

/* The in-process path: the same steps as the child processes, through the loaded libLLVM. Phase one. */
static bool inproc_generate(const ObjectOptions *options, MsSpan triple, MsSpan ir, MsSpan object, ObjectCode *code,
                            MsStrBuild *why) {
  LlvmSettings settings = {.library = options->llvm, .triple = triple,
                           .pipeline = !options->speed ? NULL : options->debug ? debug_pipeline + sizeof("-passes=") - 1 : "default<O3>",
                           .vectorize = options->vectorize, .verify = options->verify,
                           .codegen_level = options->speed ? (options->debug ? 1 : 3) : 0,
                           .fast_codegen = options->debug,
                           .assembly = options->tables != NULL};
  LlvmBuffer first = {0};
  const bool ok = llvm_compile(&settings, ir, &first, why);
  *code = (ObjectCode){.data = first.data, .size = first.size, .handle = first.handle};
  if (ok && options->tables == NULL) {
    return write_object(object, &first, why);
  }
  return ok;
}

/* Phase two in-process: the tables are added to the assembly and the result is assembled. */
static bool inproc_finish(const ObjectOptions *options, MsSpan triple, MsSpan object, ObjectCode *code, MsStrBuild *why) {
  MsArena arena = ms_arena_new();
  MsStrBuild text = ms_strbuild_new();
  MsStrBuild wrapped = ms_strbuild_new();
  bool ok = link_asm_tables(&arena, options->module, options->tables,
                            ms_span_of((const uint8_t *)code->data, code->size), options->unit,
                            options->units, &text, why);
  LlvmBuffer second = {0};
  if (ok) {
    wrap_assembly(triple, ms_strbuild_span(&text), &wrapped);
    LlvmSettings plain = {.library = options->llvm, .triple = triple};
    ok = llvm_compile(&plain, ms_strbuild_span(&wrapped), &second, why) && write_object(object, &second, why);
  }
  llvm_buffer_free(&second);
  ms_strbuild_free(&wrapped);
  ms_strbuild_free(&text);
  ms_arena_free(&arena);
  return ok;
}

bool link_generate(const ObjectOptions *options, MsSpan ir, MsSpan object, ObjectCode *code, MsStrBuild *why) {
  *code = (ObjectCode){0};
  MsSpan triple = emit_host_triple();
  if (triple.len == 0) {
    ms_strbuild_append_text(why, "native builds are not supported on this host");
    return false;
  }
  if (options->llvm.len != 0) {
    return inproc_generate(options, triple, ir, object, code, why);
  }
  MsStrBuild flag = ms_strbuild_new();
  ms_strbuild_append_text(&flag, "-mtriple=");
  ms_strbuild_append(&flag, triple);
  MsString triple_flag = ms_strbuild_finish(&flag);
  MsString text = scratch_file(options, "program", ".ll");
  MsString bitcode = scratch_file(options, "program", ".bc");
  MsString assembly = scratch_file(options, "program", ".s");
  MsString log = scratch_file(options, "tool", ".log");
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
    ok = generate(options, ms_string_span(&triple_flag), input, ms_string_span(&assembly), ms_string_span(&log),
                  "-filetype=asm", why);
  } else {
    ok = ok && generate(options, ms_string_span(&triple_flag), input, object, ms_string_span(&log), "-filetype=obj", why);
  }
  ms_path_remove(ms_string_span(&text));
  ms_path_remove(ms_string_span(&bitcode));
  if (!ok) {
    ms_path_remove(ms_string_span(&assembly));
  }
  ms_path_remove(ms_string_span(&log));
  ms_string_release(&text);
  ms_string_release(&bitcode);
  ms_string_release(&assembly);
  ms_string_release(&log);
  ms_string_release(&triple_flag);
  return ok;
}

bool link_finish(const ObjectOptions *options, MsSpan object, ObjectCode *code, MsStrBuild *why) {
  bool ok = true;
  if (options->tables != NULL) {
    MsSpan triple = emit_host_triple();
    if (options->llvm.len != 0) {
      ok = inproc_finish(options, triple, object, code, why);
    } else {
      MsStrBuild flag = ms_strbuild_new();
      ms_strbuild_append_text(&flag, "-mtriple=");
      ms_strbuild_append(&flag, triple);
      MsString triple_flag = ms_strbuild_finish(&flag);
      MsString log = scratch_file(options, "tool", ".log");
      ok = tables_object(options, ms_string_span(&triple_flag), object, ms_string_span(&log), why);
      ms_path_remove(ms_string_span(&log));
      ms_string_release(&log);
      ms_string_release(&triple_flag);
    }
  }
  link_discard(code);
  return ok;
}

bool link_make_object(const ObjectOptions *options, MsSpan ir, MsSpan object, MsStrBuild *why) {
  ObjectCode code;
  return link_generate(options, ir, object, &code, why) && link_finish(options, object, &code, why);
}
