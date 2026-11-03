/* Round-trips every ms_abi.h signature type (crates/ms-cli/tests/extern_link.rs). */
#include "ms_abi.h"

/* Declared here rather than through <stdlib.h>: the compiler's own headers are the only ones
   every CI host has. The runtime links the C library that defines them. */
void *malloc(size_t size);
void free(void *p);

#if defined(_WIN32) && defined(__clang__)
int _fltused = 0;
#endif

int8_t abi_i8(int8_t x) { return (int8_t)(x - 1); }
int16_t abi_i16(int16_t x) { return (int16_t)(x - 1); }
int32_t abi_i32(int32_t x) { return x - 1; }
uint8_t abi_u8(uint8_t x) { return (uint8_t)(x + 1); }
uint16_t abi_u16(uint16_t x) { return (uint16_t)(x + 1); }
uint32_t abi_u32(uint32_t x) { return x + 1; }
uint64_t abi_u64(uint64_t x) { return x + 1; }
float abi_f32(float x) { return x / 2; }
bool abi_not(bool x) { return !x; }

/* A sum that only C-typed arguments get right: each is read at its own width. */
int64_t abi_mixed(int8_t a, uint8_t b, int16_t c, uint16_t d, int32_t e, uint32_t f, float g) {
    return (int64_t)a + b + c + d + e + f + (int64_t)g;
}

void abi_reverse(const ms_bytes *in, ms_bytes *out) {
    size_t n = ms_bytes_len(in);
    uint8_t *buf = malloc(n ? n : 1);
    for (size_t i = 0; i < n; i++) buf[i] = ms_bytes_data(in)[n - 1 - i];
    ms_bytes_new(buf, n, out);
    free(buf);
}

size_t abi_cstring_length(const ms_str *s) {
    char *c = ms_str_cstring(s);
    if (!c) return (size_t)-1;
    size_t n = 0;
    while (c[n]) n++;
    free(c);
    return n;
}

/* Doubles each Int32; returns the sum of a List[UInt8]. */
void abi_double(const ms_list *in, ms_list *out) {
    for (size_t i = 0; i < ms_list_len(in); i++) {
        ms_value v = ms_list_get(in, i);
        v.as.i *= 2;
        ms_list_push(out, &v);
    }
}

uint64_t abi_sum(const ms_list *in) {
    uint64_t total = 0;
    for (size_t i = 0; i < ms_list_len(in); i++) total += ms_list_get(in, i).as.u;
    return total;
}

void abi_shout(const ms_list *in, ms_list *out) {
    for (size_t i = 0; i < ms_list_len(in); i++) {
        ms_value v = ms_list_get(in, i);
        uint8_t *up = malloc(v.as.buf.len + 1);
        for (size_t k = 0; k < v.as.buf.len; k++) {
            uint8_t c = v.as.buf.data[k];
            up[k] = c >= 'a' && c <= 'z' ? c - 32 : c;
        }
        up[v.as.buf.len] = '!';
        ms_value w = {MS_STRING, {.buf = {up, v.as.buf.len + 1}}};
        ms_list_push(out, &w);
        free(up);
        ms_value_free(&v);
    }
}

/* Pushing 300 into a List[UInt8] faults. */
void abi_overflow(ms_list *out) {
    ms_value v = {MS_UINT, {.u = 300}};
    ms_list_push(out, &v);
}

/* Counter objects: drops are counted so the test can see each runs once. */
static int64_t drops;
typedef struct { int64_t value; } Counter;
static void counter_drop(void *payload) { drops += 1 + 0 * ((Counter *)payload)->value; }

ms_object *abi_counter(int64_t start) {
    ms_object *o = ms_object_new(sizeof(Counter), counter_drop);
    ((Counter *)ms_payload(o))->value = start;
    return o;
}

int64_t abi_counter_bump(ms_object *o) { return ++((Counter *)ms_payload(o))->value; }
int64_t abi_drops(void) { return drops; }

int64_t abi_total(const ms_list *counters) {
    int64_t total = 0;
    for (size_t i = 0; i < ms_list_len(counters); i++) {
        total += ((Counter *)ms_payload(ms_list_get(counters, i).as.object))->value;
    }
    return total;
}

ms_object *abi_null(void) { return NULL; }

/* Status 0: ok through out. 1: Failed(code, message). 2: Empty. 3: Unknown(code). */
uint8_t abi_parse(const ms_str *text, ms_object **out, int64_t *code_out, ms_str *message_out) {
    size_t n = ms_str_len(text);
    const uint8_t *d = ms_str_data(text);
    if (n == 0) return 2;
    if (d[0] == '?') { *code_out = 7; return 3; }
    int64_t value = 0;
    for (size_t i = 0; i < n; i++) {
        if (d[i] < '0' || d[i] > '9') {
            static const char why[] = "not a digit";
            *code_out = (int64_t)i;
            ms_string_new((const uint8_t *)why, sizeof why - 1, message_out);
            return 1;
        }
        value = value * 10 + (d[i] - '0');
    }
    *out = abi_counter(value);
    return 0;
}

/* Writes a message but reports ok; the message must be dropped, not leaked or read. */
uint8_t abi_noisy(ms_str *out, int64_t *code_out, ms_str *message_out) {
    (void)code_out;
    ms_string_new((const uint8_t *)"ignored", 7, message_out);
    ms_string_new((const uint8_t *)"fine", 4, out);
    return 0;
}

/* Reports ok without writing out: the caller sees the empty value. */
uint8_t abi_lazy(ms_str *out, int64_t *code_out, ms_str *message_out) {
    (void)out; (void)code_out; (void)message_out;
    return 0;
}

uint8_t abi_bad_status(int64_t *code_out, ms_str *message_out) {
    (void)code_out; (void)message_out;
    return 9;
}

void abi_fault(void) {
    static const char text[] = "the shim gave up";
    ms_fault(text, sizeof text - 1);
}

/* ---- Functions (ms_call) ---- */

/* f(f(x)). */
int64_t abi_twice(ms_fn *f, int64_t x) {
    ms_value arg = {MS_INT, {.i = x}}, r;
    ms_call(f, &arg, 1, &r);
    arg.as.i = r.as.i;
    ms_call(f, &arg, 1, &r);
    return r.as.i;
}

/* Calls f("ab", -3, true, 2.5, bytes "xy") and returns its string. */
void abi_describe(ms_fn *f, ms_str *out) {
    ms_value args[5] = {
        {MS_STRING, {.buf = {(const uint8_t *)"ab", 2}}},
        {MS_INT, {.i = -3}},
        {MS_BOOL, {.b = true}},
        {MS_FLOAT, {.f = 2.5}},
        {MS_BYTES, {.buf = {(const uint8_t *)"xy", 2}}},
    };
    ms_value r;
    ms_call(f, args, 5, &r);
    ms_string_new(r.as.buf.data, r.as.buf.len, out);
    ms_value_free(&r);
}

/* A kept callback: abi_keep clones it, abi_fire calls it with an object, abi_forget drops it. */
static ms_fn *kept;
void abi_keep(ms_fn *f) { kept = ms_fn_clone(f); }
void abi_fire(ms_object *counter) {
    ms_value arg = {MS_OBJECT, {.object = counter}};
    ms_call(kept, &arg, 1, NULL);
}
void abi_forget(void) {
    ms_fn_drop(kept);
    kept = NULL;
}

/* An argument of the wrong kind faults. */
void abi_call_wrong(ms_fn *f) {
    ms_value arg = {MS_STRING, {.buf = {(const uint8_t *)"x", 1}}};
    ms_call(f, &arg, 1, NULL);
}

/* Runs f; a fault in it ends the program. */
void abi_call_plain(ms_fn *f) { ms_call(f, NULL, 0, NULL); }

/* ---- Stop hooks ---- */

static volatile int stopped;
static void on_stop(void *arg) { *(volatile int *)arg = 1; }

static ms_stop_hook *hook;

/* Registers the hook before the program reports it is ready. */
void abi_arm_stop(void) { hook = ms_on_stop(on_stop, (void *)&stopped); }

/* Asks for a stop the way a user would: SIGINT on Unix, Ctrl-Break to this process's own group
   on Windows (the test starts it as a group leader). Windows delivers it on another thread. */
#ifdef _WIN32
int __stdcall GenerateConsoleCtrlEvent(unsigned long event, unsigned long group);
unsigned long __stdcall GetCurrentProcessId(void);
static int request_stop(void) { return GenerateConsoleCtrlEvent(1, GetCurrentProcessId()) != 0; }
#else
int raise(int sig);
static int request_stop(void) { return raise(2) == 0; }
#endif

/* Requests a stop, then blocks until the hook runs, as a C event loop would. */
int64_t abi_wait_for_stop(void) {
    if (!request_stop()) {
        static const char text[] = "the stop request could not be sent";
        ms_fault(text, sizeof text - 1);
    }
    while (!stopped) {
    }
    ms_on_stop_remove(hook);
    return stopped;
}
