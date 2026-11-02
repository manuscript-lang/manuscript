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
