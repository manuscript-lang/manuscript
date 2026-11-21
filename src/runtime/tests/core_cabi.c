/* Unit test for src/runtime/core/cabi.c, the C ABI of user extern shims; `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/bytes.h"
#include "ms_rt/cabi.h"
#include "ms_rt/list.h"
#include "rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_cabi.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static bool faults(void (*body)(void)) {
    jmp_buf jump;
    ms_test_fault = &jump;
    if (setjmp(jump) == 0) {
        body();
        ms_test_fault = NULL;
        return false;
    }
    ms_test_fault = NULL;
    return true;
}

static bool fault_says(const char *text) { return strcmp(ms_test_fault_message, text) == 0; }

/* ---- strings, bytes and values ---- */

static void test_strings(void) {
    MsStr text;
    msrt_string_empty(&text);
    ms_string_new_v1((const uint8_t *)"hello", 5, &text);
    char *c = ms_str_cstring_v1(&text);
    CHECK(c != NULL && strcmp(c, "hello") == 0);
    free(c);

    ms_string_new_v1((const uint8_t *)"a\0b", 3, &text);
    CHECK(ms_str_cstring_v1(&text) == NULL);
    ms_str_release(&text);
}

static void bad_utf8(void) {
    MsStr text;
    msrt_string_empty(&text);
    ms_string_new_v1((const uint8_t *)"\xff\xfe", 2, &text);
}

static void test_bytes(void) {
    MsList bytes = {0};
    ms_bytes_new_v1((const uint8_t *)"\x01\x02\x03", 3, &bytes);
    CHECK(bytes.len == 3 && bytes.ptr[2] == 3);
    ms_bytes_new_v1(NULL, 0, &bytes);
    CHECK(bytes.len == 0 && bytes.ptr == NULL);
}

/* ---- lists ---- */

static void push_int(MsListRef *list, int64_t value) {
    MsValue v = {.kind = VALUE_INT, .as.i = value};
    ms_list_push_v1(list, &v);
}

static void test_lists(void) {
    MsList ints;
    msrt_list_new(&ints);
    MsListRef list = {&ints, VALUE_INT | 4u << 8};
    push_int(&list, -5);
    push_int(&list, 7);
    CHECK(ms_list_len_v1(&list) == 2 && ms_list_kind_v1(&list) == VALUE_INT);
    MsValue first = ms_list_get_v1(&list, 0);
    CHECK(first.kind == VALUE_INT && first.as.i == -5);
    CHECK(ms_list_get_v1(&list, 1).as.i == 7);
    msrt_list_free_raw(&ints);

    MsList strings;
    msrt_list_new(&strings);
    MsListRef names = {&strings, VALUE_STRING};
    MsValue name = {.kind = VALUE_STRING, .as.buf = {(const uint8_t *)"ab", 2}};
    ms_list_push_v1(&names, &name);
    MsValue got = ms_list_get_v1(&names, 0);
    CHECK(got.kind == VALUE_STRING && got.as.buf.len == 2 && memcmp(got.as.buf.data, "ab", 2) == 0);
    ms_value_free_v1(&got);
    CHECK(got.kind == VALUE_VOID);
    msrt_list_drop(&strings, &msrt_desc_string);
}

static MsList fault_ints;

static void push_out_of_range(void) {
    MsListRef list = {&fault_ints, VALUE_INT | 1u << 8};
    push_int(&list, 300);
}

static void push_wrong_kind(void) {
    MsListRef list = {&fault_ints, VALUE_INT | 8u << 8};
    MsValue v = {.kind = VALUE_BOOL, .as.b = true};
    ms_list_push_v1(&list, &v);
}

static void get_out_of_range(void) {
    MsListRef list = {&fault_ints, VALUE_INT | 8u << 8};
    (void)ms_list_get_v1(&list, 4);
}

/* ---- objects ---- */

static int payload_drops;

static void count_drop(void *payload) { payload_drops += *(int *)payload; }

static void test_objects(void) {
    MsObj *object = ms_object_new_v1(sizeof(int), count_drop);
    int *payload = ms_payload_v1(object);
    CHECK(((uintptr_t)payload & 15u) == 0 && *payload == 0);
    *payload = 3;
    object->drop(object);
    CHECK(payload_drops == 3);
}

/* ---- function values ---- */

/* A closure: the header, then the code the thunk runs. This one adds its two Int arguments. */
typedef struct Closure {
    MsObj header;
    void (*code)(uint8_t *closure, uint8_t *cells);
} Closure;

static void add_code(uint8_t *closure, uint8_t *cells) {
    (void)closure;
    int64_t a, b;
    memcpy(&a, cells, sizeof a);
    memcpy(&b, cells + 24, sizeof b);
    const int64_t sum = a + b;
    memcpy(cells + 6 * 24, &sum, sizeof sum);
}

static void closure_drop(MsObj *object) { msrt_free(object); }

static void test_call(void) {
    Closure *closure = msrt_alloc_zeroed(sizeof *closure);
    closure->header.drop = closure_drop;
    closure->code = add_code;
    /* Two parameters of Int (kind 2, width 8), result Int: bytes kind | width << 4. */
    const uint64_t int_byte = 2u | 8u << 4;
    const uint64_t sig = 2u | int_byte << 8 | int_byte << 16 | int_byte << 56;
    MsObj *function = msrt_fn_new(&closure->header, sig);
    MsValue args[2] = {{.kind = VALUE_INT, .as.i = 40}, {.kind = VALUE_INT, .as.i = 2}};
    MsValue result = {0};
    ms_call_v1(function, args, 2, &result);
    CHECK(result.kind == VALUE_INT && result.as.i == 42);
    ms_call_v1(function, args, 2, NULL);
    function->drop(function);
}

static MsObj *wrong_arity_function;

static void call_wrong_count(void) {
    MsValue arg = {.kind = VALUE_INT, .as.i = 1};
    ms_call_v1(wrong_arity_function, &arg, 1, NULL);
}

/* ---- stop hooks ---- */

static int ran;

static void add_hook(void *argument) { ran += (int)(intptr_t)argument; }

static void test_stop_hooks(void) {
    void *a = ms_on_stop_v1(add_hook, (void *)(intptr_t)2);
    void *b = ms_on_stop_v1(add_hook, (void *)(intptr_t)10);
    CHECK(a != NULL && b != NULL && a != b);
    ms_stop_hooks_run();
    CHECK(ran == 12);
    ms_on_stop_remove_v1(a);
    ms_stop_hooks_run();
    CHECK(ran == 22);
    ms_on_stop_remove_v1(b);
    ms_on_stop_remove_v1(NULL);
    ms_stop_hooks_run();
    CHECK(ran == 22);
    /* All 32 slots can be taken, and the next request gets NULL. */
    void *held[32];
    for (int i = 0; i < 32; i++) {
        held[i] = ms_on_stop_v1(add_hook, NULL);
        CHECK(held[i] != NULL);
    }
    CHECK(ms_on_stop_v1(add_hook, NULL) == NULL);
    for (int i = 0; i < 32; i++) {
        ms_on_stop_remove_v1(held[i]);
    }
}

int main(void) {
    test_strings();
    CHECK(faults(bad_utf8));
    CHECK(fault_says("ms_string_new received 2 bytes that are not UTF-8; use ms_bytes_new for binary data"));
    test_bytes();
    test_lists();
    msrt_list_new(&fault_ints);
    CHECK(faults(push_out_of_range) && fault_says("ms_list_push value 300 is out of range for a List[Int8]"));
    CHECK(faults(push_wrong_kind) && fault_says("ms_list_push received MS_BOOL for a List[Int]"));
    CHECK(faults(get_out_of_range) && fault_says("ms_list_get index 4 is out of range for a list of 0 elements"));
    test_objects();
    test_call();
    Closure *closure = msrt_alloc_zeroed(sizeof *closure);
    closure->header.drop = closure_drop;
    wrong_arity_function = msrt_fn_new(&closure->header, 0);
    CHECK(faults(call_wrong_count) && fault_says("ms_call received 1 arguments for a function of 0 parameters"));
    wrong_arity_function->drop(wrong_arity_function);
    test_stop_hooks();
    puts("core_cabi: ok");
    return 0;
}
