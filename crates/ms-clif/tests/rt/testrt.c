/* Minimal stand-in for ms-rt used by the backend's differential tests.
   Implements only the symbols generated code imports, per crates/ms-rt/ABI.md. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Obj { uint64_t rc; void (*drop)(struct Obj *); } Obj;

uint8_t msrt_cancel_flag = 0;
int64_t msrt_call_depth = 0;
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
static void die(const char *msg, size_t len) {
  fflush(stdout);
  fprintf(stderr, "%.*s\n", (int)len, msg);
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
void msrt_fault_depth(void) { die("call depth limit exceeded (200000 nested calls)", 47); }
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

int msrt_start(int64_t (*main_fn)(void), const void *tables, int argc, char **argv) {
  (void)tables; (void)argc; (void)argv;
  int64_t r = main_fn();
  fflush(stdout);
  if (r < 0 || r > 125) { fprintf(stderr, "exit code out of range\n"); return 70; }
  return (int)r;
}
