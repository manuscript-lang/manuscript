/* Minimal stand-in for ms-rt used by the backend's differential tests.
   Implements only the symbols generated code imports, per crates/ms-rt/ABI.md. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#endif

typedef struct Obj { uint64_t rc; void (*drop)(struct Obj *); } Obj;

uint8_t msrt_cancel_flag = 0;
uintptr_t msrt_stack_limit = 0;
int64_t msrt_live_allocs = 0;

#define MAX_CLEANUPS 256
static struct { void (*f)(uint8_t *); uint8_t *arg; } cleanups[MAX_CLEANUPS];
static size_t ncleanups = 0;

uint8_t *msrt_alloc(size_t n) {
  msrt_live_allocs++;
  uint8_t *p = malloc(n ? n : 1);
  if (!p) abort();
  return p;
}
void msrt_free(uint8_t *p) { if (p) { msrt_live_allocs--; free(p); } }
uint8_t *msrt_realloc(uint8_t *p, size_t n) {
  if (!p) return msrt_alloc(n);
  uint8_t *q = realloc(p, n ? n : 1);
  if (!q) abort();
  return q;
}
void msrt_drop_slow(Obj *o) { if (o->drop) o->drop(o); }

static void run_cleanups(void) {
  while (ncleanups > 0) {
    ncleanups--;
    cleanups[ncleanups].f(cleanups[ncleanups].arg);
  }
}
typedef struct { uint32_t abi, reserved; const void *funcs; size_t nfuncs; const void *lines; size_t nlines; const char *strings; size_t slen; } Tables;
typedef struct { uintptr_t addr; uint32_t size, name, file, line; } FuncEntry;
typedef struct { uintptr_t pc; uint32_t line, file; } LineEntry;
static const Tables *tables;

static const FuncEntry *find_func(uintptr_t pc) {
  const FuncEntry *fe = tables->funcs;
  for (size_t i = 0; i < tables->nfuncs; i++)
    if (pc > fe[i].addr && pc <= fe[i].addr + fe[i].size) return &fe[i];
  return 0;
}
static void show_frame(uintptr_t pc, const FuncEntry *fe) {
  const LineEntry *le = tables->lines;
  const LineEntry *best = 0;
  for (size_t k = 0; k < tables->nlines; k++)
    if (le[k].pc <= pc - 1 && (!best || le[k].pc >= best->pc)) best = &le[k];
  const char *file = fe->file == UINT32_MAX ? "?" : tables->strings + fe->file;
  fprintf(stderr, "  at %s %s:%u\n", tables->strings + fe->name, file, best ? best->line : fe->line);
}

/* Windows native frames need their unwind records before reaching generated
   code. Once there, stop at native/glue boundaries; never invent a partially
   restored native register context from a generated frame pointer. */
static void trace(void) {
  if (!tables) return;
#ifdef _WIN32
  CONTEXT context;
  RtlCaptureContext(&context);
  ULONG_PTR lo, hi;
  GetCurrentThreadStackLimits(&lo, &hi);
#if defined(_M_ARM64) || defined(__aarch64__)
#define CTX_PC Pc
#define CTX_SP Sp
#define CTX_FP Fp
#else
#define CTX_PC Rip
#define CTX_SP Rsp
#define CTX_FP Rbp
#endif
  for (int depth = 0; depth < 256; depth++) {
    uintptr_t pc = context.CTX_PC, sp = context.CTX_SP;
    if (!pc || sp < lo || sp >= hi || sp % 8) return;
    if (find_func(pc)) break;
    DWORD64 image = 0, establisher = 0;
    PRUNTIME_FUNCTION entry = RtlLookupFunctionEntry(pc, &image, 0);
    if (!entry) return;
    void *handler = 0;
    RtlVirtualUnwind(0, image, pc, entry, &context, &handler, &establisher, 0);
    if (context.CTX_SP < sp || (context.CTX_SP == sp && context.CTX_PC == pc)) return;
  }
  uintptr_t pc = context.CTX_PC;
  uintptr_t *fp = (uintptr_t *)context.CTX_FP;
  for (int depth = 0; depth < 64; depth++) {
    const FuncEntry *fe = find_func(pc);
    if (!fe) break;
    show_frame(pc, fe);
    uintptr_t address = (uintptr_t)fp;
    if (address % 8 || address < lo || address > hi || hi - address < 16) break;
    uintptr_t *next = (uintptr_t *)fp[0];
    pc = fp[1];
    if (next <= fp) break;
    fp = next;
  }
#undef CTX_PC
#undef CTX_SP
#undef CTX_FP
#else
  uintptr_t *fp = __builtin_frame_address(0);
  for (int depth = 0; fp && depth < 64; depth++) {
    uintptr_t pc = fp[1];
    const FuncEntry *fe = find_func(pc);
    if (fe) show_frame(pc, fe);
    uintptr_t *next = (uintptr_t *)fp[0];
    if (next <= fp) break;
    fp = next;
  }
#endif
}
static void die(const char *msg, size_t len) {
  fflush(stdout);
  fprintf(stderr, "%.*s\n", (int)len, msg);
  trace();
  run_cleanups();
  fflush(stdout);
  exit(70);
}
void msrt_fault(const char *msg, size_t len) { die(msg, len); }
void msrt_fault_int_overflow(void) { die("integer overflow", 16); }
void msrt_fault_div_zero(void) { die("division by zero", 16); }
void msrt_fault_rem_zero(void) { die("remainder by zero", 17); }
void msrt_fault_div_overflow(int64_t a, int64_t b) { (void)a; (void)b; die("integer overflow", 16); }
void msrt_index_fault(int64_t i, int64_t n) {
  char buf[128];
  int k = snprintf(buf, sizeof buf, "index %lld out of range for length %lld", (long long)i, (long long)n);
  die(buf, (size_t)k);
}
void msrt_fault_unwrap_none(void) { die("unwrap of none", 14); }
void msrt_fault_depth(void) { die("stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead", 153); }
void msrt_cancelled(void) { fflush(stdout); run_cleanups(); exit(130); }

size_t msrt_cleanup_push(void (*f)(uint8_t *), uint8_t *arg) {
  /* The argument slot lives in the caller's frame; copy nothing, as ABI.md specifies. */
  cleanups[ncleanups].f = f;
  cleanups[ncleanups].arg = arg;
  return ++ncleanups;
}
void msrt_cleanup_run(size_t handle) {
  while (ncleanups >= handle && handle > 0) {
    ncleanups--;
    cleanups[ncleanups].f(cleanups[ncleanups].arg);
  }
}

/* Test hooks used by call.rt in fixtures. */
void msrt_print_int(int64_t v) { printf("%lld\n", (long long)v); }
void msrt_print_float(double v) { printf("%.17g\n", v); }
void msrt_print_bool(uint8_t v) { printf("%s\n", v ? "true" : "false"); }
void msrt_print_str(const Obj *s) {
  const uint64_t *w = (const uint64_t *)s;
  printf("%.*s\n", (int)w[2], (const char *)(w + 4));
}
int64_t msrt_live(void) { return msrt_live_allocs; }

int msrt_start(int64_t (*main_fn)(void), const void *t, int argc, char **argv) {
  tables = t; (void)argc; (void)argv;
  struct timespec t0, t1;
#ifdef _WIN32
  timespec_get(&t0, TIME_UTC);
#else
  clock_gettime(CLOCK_MONOTONIC, &t0);
#endif
  int64_t r = main_fn();
#ifdef _WIN32
  timespec_get(&t1, TIME_UTC);
#else
  clock_gettime(CLOCK_MONOTONIC, &t1);
#endif
  fflush(stdout);
  if (getenv("MSRT_TIME")) {
    long long us = (long long)(t1.tv_sec - t0.tv_sec) * 1000000LL + (t1.tv_nsec - t0.tv_nsec) / 1000;
    fprintf(stderr, "time_us %lld\n", us);
  }
  if (getenv("MSRT_LEAKCHECK") && msrt_live_allocs != 0) {
    fprintf(stderr, "leak: %lld live allocations\n", (long long)msrt_live_allocs);
    return 99;
  }
  if (r < 0 || r > 125) { fprintf(stderr, "exit code out of range\n"); return 70; }
  return (int)r;
}

#include "callback.h"

#ifdef __linux__
/* The bundled linker has no libgcc; fixtures borrow the toolchain's compiler-builtins (see support/mod.rs),
   whose unwind tables name Rust's personality routine. Nothing unwinds here. */
void rust_eh_personality(void) {}
#endif
