/* Owns the in-process LLVM calls (see llvm_inproc.h). */
#include "compiler/link/llvm_inproc.h"

#include "base/dylib.h"
#include "base/ostext.h"
#include "abi/fault.h"

#include <stdio.h>
#include <stdlib.h>

typedef void *Ref;

/* The C API functions used, resolved by name from the loaded library. */
#define LLVM_FUNCTIONS(X)                                                                                            \
  X(Ref, LLVMContextCreate, (void))                                                                                  \
  X(void, LLVMContextDispose, (Ref))                                                                                 \
  X(Ref, LLVMCreateMemoryBufferWithMemoryRangeCopy, (const char *, size_t, const char *))                            \
  X(int, LLVMParseIRInContext, (Ref, Ref, Ref *, char **))                                                           \
  X(void, LLVMDisposeModule, (Ref))                                                                                  \
  X(void, LLVMDisposeMessage, (char *))                                                                              \
  X(int, LLVMGetTargetFromTriple, (const char *, Ref *, char **))                                                    \
  X(Ref, LLVMCreateTargetMachine, (Ref, const char *, const char *, const char *, int, int, int))                   \
  X(void, LLVMDisposeTargetMachine, (Ref))                                                                           \
  X(Ref, LLVMCreateTargetDataLayout, (Ref))                                                                          \
  X(void, LLVMSetModuleDataLayout, (Ref, Ref))                                                                       \
  X(void, LLVMDisposeTargetData, (Ref))                                                                              \
  X(void, LLVMSetTarget, (Ref, const char *))                                                                        \
  X(Ref, LLVMCreatePassBuilderOptions, (void))                                                                       \
  X(void, LLVMPassBuilderOptionsSetVerifyEach, (Ref, int))                                                           \
  X(void, LLVMPassBuilderOptionsSetLoopVectorization, (Ref, int))                                                    \
  X(void, LLVMPassBuilderOptionsSetSLPVectorization, (Ref, int))                                                     \
  X(void, LLVMDisposePassBuilderOptions, (Ref))                                                                      \
  X(Ref, LLVMRunPasses, (Ref, const char *, Ref, Ref))                                                               \
  X(char *, LLVMGetErrorMessage, (Ref))                                                                              \
  X(void, LLVMDisposeErrorMessage, (char *))                                                                         \
  X(int, LLVMTargetMachineEmitToMemoryBuffer, (Ref, Ref, int, char **, Ref *))                                       \
  X(const char *, LLVMGetBufferStart, (Ref))                                                                         \
  X(size_t, LLVMGetBufferSize, (Ref))                                                                                \
  X(void, LLVMDisposeMemoryBuffer, (Ref))                                                                            \
  X(void, LLVMParseCommandLineOptions, (int, const char *const *, const char *))                                    \
  X(void, LLVMInstallFatalErrorHandler, (void (*)(const char *)))

typedef struct Api {
#define X(ret, name, args) ret(*name) args;
  LLVM_FUNCTIONS(X)
#undef X
  void (*init[5])(void); /* the host target's TargetInfo, Target, TargetMC, AsmPrinter and AsmParser */
  bool ready;
} Api;

static Api api;

#if defined(__x86_64__) || defined(_M_X64)
#define TARGET_NAME "X86"
#define TARGET_CPU "x86-64"
#else
#define TARGET_NAME "AArch64"
#define TARGET_CPU ""
#endif

/* LLVM reports an internal error (an assertion, an out-of-memory, a bad option) by calling this and then aborting.
 * `ms` reports it as its own internal error, with the exit status of a fault, instead of a bare LLVM abort. */
static void fatal_error(const char *message) {
  fprintf(stderr, "internal compiler error: LLVM: %s\nThis is a bug in ms, not in your program. Please report it at "
                  "https://github.com/manuscript-lang/manuscript/issues with the code that triggers it.\n", message);
  exit(MS_EXIT_ABORT);
}

static bool load(MsSpan path, MsStrBuild *why) {
  if (api.ready) {
    return true;
  }
  static MsDylib library; /* stays loaded: the process compiles one program */
  if (!ms_dylib_open(path, &library, why)) {
    return false;
  }
  const char *missing = NULL;
#define X(ret, name, args)                                                                                           \
  api.name = (ret(*) args)ms_dylib_symbol(&library, #name);                                                               \
  if (api.name == NULL && missing == NULL) {                                                                         \
    missing = #name;                                                                                                 \
  }
  LLVM_FUNCTIONS(X)
#undef X
  static const char *const parts[5] = {"TargetInfo", "Target", "TargetMC", "AsmPrinter", "AsmParser"};
  for (int index = 0; index < 5; index++) {
    MsStrBuild name = ms_strbuild_new();
    ms_strbuild_append_text(&name, "LLVMInitialize" TARGET_NAME);
    ms_strbuild_append_text(&name, parts[index]);
    MsOsText symbol = ms_os_text_new(ms_strbuild_span(&name));
    api.init[index] = (void (*)(void))ms_dylib_symbol(&library, symbol.ptr);
    ms_os_text_free(&symbol);
    ms_strbuild_free(&name);
    if (api.init[index] == NULL && missing == NULL) {
      missing = parts[index];
    }
  }
  if (missing != NULL) {
    ms_strbuild_append_text(why, "libLLVM lacks ");
    ms_strbuild_append_text(why, missing);
    return false;
  }
  api.LLVMInstallFatalErrorHandler(fatal_error);
  for (int index = 0; index < 5; index++) {
    api.init[index]();
  }
#if defined(__x86_64__) || defined(_M_X64)
  const char *const options[] = {"ms", "-align-loops=32"};
  api.LLVMParseCommandLineOptions(2, options, NULL);
#endif
  api.ready = true;
  return true;
}

static bool message_failure(char *message, const char *what, MsStrBuild *why) {
  ms_strbuild_append_text(why, what);
  if (message != NULL) {
    ms_strbuild_append_text(why, ": ");
    ms_strbuild_append_text(why, message);
    api.LLVMDisposeMessage(message);
  }
  return false;
}

bool llvm_compile(const LlvmSettings *settings, MsSpan ir, LlvmBuffer *out, MsStrBuild *why) {
  if (!load(settings->library, why)) {
    return false;
  }
  /* LLVM's code generator reads these from process-wide options, so each compile states all of them. */
  const char *options[4] = {"ms"};
  int count = 1;
  /* Level 0 takes only the fast register allocator. */
  options[count++] = settings->codegen_level == 0 ? "-regalloc=fast"
                     : settings->fast_codegen     ? "-regalloc=basic"
                                                  : "-regalloc=greedy";
  options[count++] = settings->fast_codegen ? "-enable-misched=0" : "-enable-misched=1";
  options[count++] = "-dse-memoryssa-walklimit=10"; /* the same limit as the process route, see object.c */
  api.LLVMParseCommandLineOptions(count, options, NULL);
  MsOsText triple = ms_os_text_new(settings->triple);
  char *triple_text = triple.ptr;
  char *message = NULL;
  Ref target = NULL;
  bool ok = true;
  if (api.LLVMGetTargetFromTriple(triple_text, &target, &message)) {
    ok = message_failure(message, "unknown target", why);
  }
  Ref context = api.LLVMContextCreate();
  Ref module = NULL;
  Ref machine = NULL;
  if (ok) {
    Ref buffer = api.LLVMCreateMemoryBufferWithMemoryRangeCopy((const char *)ir.ptr, ir.len, "program");
    message = NULL;
    if (api.LLVMParseIRInContext(context, buffer, &module, &message)) {
      ok = message_failure(message, "cannot parse the IR", why);
    }
  }
  if (ok) {
    machine = api.LLVMCreateTargetMachine(target, triple_text, TARGET_CPU, "", settings->codegen_level,
                                          2 /* PIC */, 0);
    Ref layout = api.LLVMCreateTargetDataLayout(machine);
    api.LLVMSetModuleDataLayout(module, layout);
    api.LLVMDisposeTargetData(layout);
    api.LLVMSetTarget(module, triple_text);
  }
  if (ok && settings->pipeline != NULL) {
    Ref pass_options = api.LLVMCreatePassBuilderOptions();
    api.LLVMPassBuilderOptionsSetVerifyEach(pass_options, settings->verify);
    api.LLVMPassBuilderOptionsSetLoopVectorization(pass_options, settings->vectorize);
    api.LLVMPassBuilderOptionsSetSLPVectorization(pass_options, settings->vectorize);
    Ref error = api.LLVMRunPasses(module, settings->pipeline, machine, pass_options);
    api.LLVMDisposePassBuilderOptions(pass_options);
    if (error != NULL) {
      ok = message_failure(api.LLVMGetErrorMessage(error), "optimizer failed", why);
    }
  }
  Ref buffer = NULL;
  if (ok) {
    message = NULL;
    if (api.LLVMTargetMachineEmitToMemoryBuffer(machine, module, settings->assembly ? 0 : 1, &message, &buffer)) {
      ok = message_failure(message, "code generation failed", why);
    }
  }
  if (ok) {
    *out = (LlvmBuffer){.data = api.LLVMGetBufferStart(buffer), .size = api.LLVMGetBufferSize(buffer), .handle = buffer};
  }
  if (machine != NULL) {
    api.LLVMDisposeTargetMachine(machine);
  }
  if (module != NULL) {
    api.LLVMDisposeModule(module);
  }
  api.LLVMContextDispose(context);
  ms_os_text_free(&triple);
  return ok;
}

void llvm_buffer_free(LlvmBuffer *buffer) {
  if (buffer->handle != NULL) {
    api.LLVMDisposeMemoryBuffer(buffer->handle);
  }
  *buffer = (LlvmBuffer){0};
}
