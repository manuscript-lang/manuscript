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

/* An object header: a clone entry (null for a value with one owner) and a drop entry. */
typedef struct Obj { struct Obj *(*clone)(struct Obj *); void (*drop)(struct Obj *); } Obj;

/* The isolate header block: word 0 is the stack limit, byte 8 the cancel flag. */
static struct { uintptr_t limit; uint8_t cancel; } isolate_hdr;
void *msrt_isolate_hdr(void) { return &isolate_hdr; }
/* Generated code finds its header block through the last 16 bytes of the 256 MiB-aligned region
   its stack lies in (`ms_rt_abi::symbols::STACK_REGION`), so `main` has to run on a stack inside
   such a region, below the cell page that holds the pointer. */
#define STACK_REGION ((uintptr_t)256 << 20)
#define STACK_GUARD ((uintptr_t)65536)
#define CELL_PAGE ((uintptr_t)4096)
static int64_t (*slot_main)(void);
static int64_t slot_result;
#ifndef _WIN32
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>
static void *slot_thread(void *arg) { (void)arg; slot_result = slot_main(); return 0; }
static int64_t run_on_slot(int64_t (*f)(void)) {
  char *raw = mmap(0, 2 * STACK_REGION, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
  if (raw == MAP_FAILED) abort();
  uintptr_t base = ((uintptr_t)raw + STACK_REGION - 1) & ~(STACK_REGION - 1);
  *(void **)(base + STACK_REGION - 16) = &isolate_hdr;
  slot_main = f;
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  /* macOS refuses a stack whose size is not a multiple of its page (16 KiB on arm64), so the
     stack ends at the page boundary below the cell page. */
  uintptr_t page = (uintptr_t)sysconf(_SC_PAGESIZE);
  uintptr_t size = (STACK_REGION - STACK_GUARD - CELL_PAGE) & ~(page - 1);
  if (pthread_attr_setstack(&attr, (void *)(base + STACK_GUARD), size) != 0) abort();
  pthread_t th;
  if (pthread_create(&th, &attr, slot_thread, 0) != 0) abort();
  pthread_join(th, 0);
  return slot_result;
}
#else
/* Windows threads cannot be given a stack address, so `main` runs on a reserved region after a
   stack switch; the top 8 MiB are committed (the stub installs no guard page growth). */
#define STACK_COMMIT ((uintptr_t)8 << 20)
/* The bounds of the stack `main` runs on; the thread's own limits do not describe it. */
static uintptr_t slot_lo, slot_hi;
static int64_t call_on_stack(void *top, int64_t (*f)(void)) {
  int64_t r;
#if defined(__x86_64__)
  __asm__ volatile(
      "mov %%rsp, %%rbx\n\t"
      "mov %[top], %%rsp\n\t"
      "sub $32, %%rsp\n\t"
      "call *%[f]\n\t"
      "mov %%rbx, %%rsp\n\t"
      : "=a"(r)
      : [top] "D"(top), [f] "S"(f)
      : "rbx", "rcx", "rdx", "r8", "r9", "r10", "r11", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4",
        "xmm5", "memory", "cc");
#elif defined(__aarch64__)
  register int64_t x0 __asm__("x0");
  __asm__ volatile(
      "mov x19, sp\n\t"
      "mov sp, %[top]\n\t"
      "blr %[f]\n\t"
      "mov sp, x19\n\t"
      : "=r"(x0)
      : [top] "r"(top), [f] "r"(f)
      : "x19", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13",
        "x14", "x15", "x16", "x17", "x30", "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v16",
        "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29",
        "v30", "v31", "memory", "cc");
  r = x0;
#else
#error "unsupported Windows architecture"
#endif
  return r;
}
static int64_t run_on_slot(int64_t (*f)(void)) {
  char *raw = VirtualAlloc(0, 2 * STACK_REGION, MEM_RESERVE, PAGE_READWRITE);
  if (!raw) abort();
  uintptr_t base = ((uintptr_t)raw + STACK_REGION - 1) & ~(STACK_REGION - 1);
  uintptr_t top = base + STACK_REGION - CELL_PAGE;
  if (!VirtualAlloc((void *)(top - STACK_COMMIT), STACK_COMMIT + CELL_PAGE, MEM_COMMIT, PAGE_READWRITE)) abort();
  *(void **)(base + STACK_REGION - 16) = &isolate_hdr;
  slot_lo = top - STACK_COMMIT;
  slot_hi = top;
  return call_on_stack((void *)top, f);
}
#endif
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
/* One-character ASCII strings, two bytes each: the character and its NUL. */
#define C2(n) {n, 0}
#define C8(n) C2(n), C2(n + 1), C2(n + 2), C2(n + 3), C2(n + 4), C2(n + 5), C2(n + 6), C2(n + 7)
#define C64(n) C8(n), C8(n + 8), C8(n + 16), C8(n + 24), C8(n + 32), C8(n + 40), C8(n + 48), C8(n + 56)
uint8_t msrt_ascii_chars[128][2] = { C64(0), C64(64) };
void msrt_str_free(uint8_t *p) { msrt_free(p); }
/* The scalar count of the string at s: two words, the second holding the length and the tag in its
   top bits (see StrVal); an inline string keeps its bytes in the words themselves. */
int64_t msrt_string_length(const uint64_t *s) {
  uint64_t t = s[1];
  const uint8_t *p = (t >> 62) == 1 ? (const uint8_t *)s : (const uint8_t *)s[0];
  uint64_t n = (t >> 62) == 1 ? (t >> 56) & 15 : t & ((1ULL << 61) - 1);
  int64_t count = 0;
  for (uint64_t i = 0; i < n; i++) if ((p[i] & 0xC0) != 0x80) count++;
  return count;
}
/* Byte equality of two strings, as `msrt_string_eq`: the generated code calls it only for two
   distinct blocks of one length, so the lengths already match unless a test calls it directly. */
uint8_t msrt_string_eq(const uint64_t *a, const uint64_t *b) {
  uint64_t ta = a[1], tb = b[1];
  uint64_t na = (ta >> 62) == 1 ? (ta >> 56) & 15 : ta & ((1ULL << 61) - 1);
  uint64_t nb = (tb >> 62) == 1 ? (tb >> 56) & 15 : tb & ((1ULL << 61) - 1);
  if (na != nb) return 0;
  const uint8_t *pa = (ta >> 62) == 1 ? (const uint8_t *)a : (const uint8_t *)a[0];
  const uint8_t *pb = (tb >> 62) == 1 ? (const uint8_t *)b : (const uint8_t *)b[0];
  return memcmp(pa, pb, na) == 0;
}
uint8_t *msrt_realloc(uint8_t *p, size_t n) {
  if (!p) return msrt_alloc(n);
  uint8_t *q = realloc(p, n ? n : 1);
  if (!q) abort();
  return q;
}
void msrt_obj_drop(Obj *o) { if (o && o->drop) o->drop(o); }
Obj *msrt_obj_clone(Obj *o) {
  if (!o) return o;
  if (!o->clone) { fputs("copy of a value that has one owner\n", stderr); exit(101); }
  return o->clone(o);
}

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
  uintptr_t lo = slot_lo, hi = slot_hi;
  if (!hi) {
    ULONG_PTR tlo, thi;
    GetCurrentThreadStackLimits(&tlo, &thi);
    lo = tlo;
    hi = thi;
  }
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
  exit(67);
}
void msrt_fault(const char *msg, size_t len) { die(msg, len); }
/* Strings the tests build are literals, never copied; the symbol only has to link. */
void msrt_str_copy(const char *p, size_t tagged, uint64_t *out) { out[0] = (uint64_t)p; out[1] = tagged; }
void msrt_fault_int_overflow(void) { die("integer overflow", 16); }
void msrt_fault_int_range(void) { die("integer range", 16); }
void msrt_fault_div_zero(void) { die("division by zero", 16); }
void msrt_fault_rem_zero(void) { die("remainder by zero", 17); }
void msrt_fault_div_overflow(int64_t a, int64_t b) { (void)a; (void)b; die("integer overflow", 16); }
void msrt_index_fault(int64_t i, int64_t n) {
  char buf[128];
  int k = snprintf(buf, sizeof buf, "index %lld out of range for length %lld", (long long)i, (long long)n);
  die(buf, (size_t)k);
}
void msrt_fault_unwrap_none(void) { die("unwrap of none", 14); }
/* The limit is never set here, so growth is never asked for; the shim runs where it is. */
void msrt_task_grow(void (*shim)(uint8_t *), uint8_t *block) { shim(block); }
void msrt_fault_depth(void) { die("stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead", 153); }
/* Nesting is never limited here, so no drop is deferred. */
uint64_t msrt_drop_enter(void) { return 0; }
void msrt_drop_defer(void (*run)(uint8_t *), uint8_t *block) { run(block); }
void msrt_drop_leave(void) {}
void msrt_slot_copy_grown(void (*copy)(const uint8_t *, uint8_t *), const uint8_t *src, uint8_t *dst) { copy(src, dst); }
/* The leak check needs every free at exit. */
uint8_t msrt_exit_frees(void) { return 1; }
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
  int64_t r = run_on_slot(main_fn);
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
  if (r < 0 || r > 125) { fprintf(stderr, "exit code out of range\n"); return 67; }
  return (int)r;
}

#include "callback.h"

#ifdef __linux__
/* The bundled linker has no libgcc; fixtures borrow the toolchain's compiler-builtins (see support/mod.rs),
   whose unwind tables name Rust's personality routine. Nothing unwinds here. */
void rust_eh_personality(void) {}
#endif
