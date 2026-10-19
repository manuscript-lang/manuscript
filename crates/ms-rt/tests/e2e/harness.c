// End-to-end harness: links against libms_rt.a and drives msrt_start like generated code.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint64_t rc; void *drop; uint64_t len; uint64_t scalars; } StrHdr;
typedef struct { uintptr_t addr; uint32_t size, name_off, file_off, line; } FuncEntry;
typedef struct { uintptr_t pc; uint32_t line, file_off; } LineEntry;
typedef struct {
    uint32_t abi_version, reserved;
    const FuncEntry *funcs; size_t func_count;
    const LineEntry *lines; size_t line_count;
    const char *strings; size_t strings_len;
} Tables;
typedef struct { uint8_t *ptr; size_t len, cap; } VecVal;

extern int32_t msrt_start(int64_t (*main_fn)(void), const Tables *t, int argc, char **argv);
extern void *msrt_string_from_bytes(const char *p, size_t n);
extern void msrt_io_write_stdout(void *s);
extern void msrt_fault(const char *p, size_t n) __attribute__((noreturn));
extern size_t msrt_cleanup_push(void (*f)(void *), void *arg);
extern int64_t msrt_string_length(void *s);
extern int64_t msrt_call_depth;
extern void msrt_fault_depth(void) __attribute__((noreturn));
extern void msrt_args(VecVal *out);

static const char *mode;

static void cleanup_a(void *arg) { fputs("cleanup a\n", stderr); }
static void cleanup_b(void *arg) { fputs("cleanup b\n", stderr); }

__attribute__((noinline)) int64_t inner(int64_t n) {
    if (n == 0) msrt_fault("boom", 4);
    return inner(n - 1) + 1;
}
__attribute__((noinline)) int64_t outer(void) { return inner(2); }

__attribute__((noinline)) int64_t busy(void) {
    volatile uint64_t x = 0;
    for (uint64_t i = 0; i < 400000000ull; i++) x += i * i;
    return (int64_t)(x & 1);
}

static int64_t deep(int64_t n) {
    msrt_call_depth += 1;
    if (msrt_call_depth > 200000) msrt_fault_depth();
    int64_t r = n == 0 ? 0 : deep(n - 1) + 1;
    msrt_call_depth -= 1;
    return r;
}

static int64_t entry(void) {
    if (!strcmp(mode, "ok")) {
        void *s = msrt_string_from_bytes("héllo\n", 7);
        msrt_io_write_stdout(s);
        return 3;
    }
    if (!strcmp(mode, "fault")) {
        msrt_cleanup_push(cleanup_a, 0);
        msrt_cleanup_push(cleanup_b, 0);
        return outer();
    }
    if (!strcmp(mode, "badexit")) return 200;
    if (!strcmp(mode, "deep")) { deep(199990); return 0; }
    if (!strcmp(mode, "toodeep")) { deep(300000); return 0; }
    if (!strcmp(mode, "args")) {
        VecVal v; msrt_args(&v);
        printf("%zu\n", v.len);
        return 0;
    }
    if (!strcmp(mode, "busy")) return busy();
    return 1;
}

int main(int argc, char **argv) {
    mode = argc > 1 ? argv[1] : "ok";
    static const char names[] = "\0outer\0inner\0busy\0t.ms\0";
    FuncEntry funcs[3] = {
        { (uintptr_t)busy, 128, 13, 18, 20 },
        { (uintptr_t)inner, 128, 7, 18, 3 },
        { (uintptr_t)outer, 64, 1, 18, 9 },
    };
    // Sort by address.
    for (int i = 0; i < 3; i++) for (int j = i + 1; j < 3; j++)
        if (funcs[j].addr < funcs[i].addr) { FuncEntry t = funcs[i]; funcs[i] = funcs[j]; funcs[j] = t; }
    Tables t = { 2, 0, funcs, 3, 0, 0, names, sizeof names };
    return msrt_start(entry, &t, argc - 1, argv + 1);
}
