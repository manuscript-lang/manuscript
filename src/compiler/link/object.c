/* Owns the object step: optimize the IR and generate the object through the loaded LLVM library (see object.h). */
#include "compiler/link/object.h"

#include "base/file.h"
#include "compiler/emit/emit.h"
#include "compiler/link/asm_tables.h"
#include "compiler/link/llvm_inproc.h"

/* A Debug build optimizes lightly: SROA, early CSE, instruction combining and CFG simplification keep frames as small
 * as `default<O2>` does (measured on a 30 MB program: 0.2% apart) for about a fifth of the optimizer's time; the code generator
 * pairs it with -O1, the basic register allocator and no machine scheduler, which cost no frame size. FastISel is
 * not used: it changes the line a fault trace reports. */
static const char debug_pipeline[] = "-passes=function(sroa,early-cse,simplifycfg,instcombine<no-verify-fixpoint>,sroa,simplifycfg)";

/* The assembly `text` as an IR module of `module asm` lines, which the code generator assembles into the object. */
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
  return inproc_generate(options, triple, ir, object, code, why);
}

bool link_finish(const ObjectOptions *options, MsSpan object, ObjectCode *code, MsStrBuild *why) {
  const bool ok = options->tables == NULL || inproc_finish(options, emit_host_triple(), object, code, why);
  link_discard(code);
  return ok;
}
