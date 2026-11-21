/* ms_rt/cabi.h: the C ABI of user `extern fn` shims (runtime/std/cabi.c). The public header is
 * crates/ms-rt-abi/include/ms_abi.h, which maps each plain name to the versioned symbol below
 * (`ms_string_new` is `ms_string_new_v1`), so a shim built against another version fails to link. The `_v1`
 * symbols are listed in runtime/symbols/cabi.txt; tools/ms/symbols.ms does not compare them with a recorded signature. */
#ifndef MS_RT_CABI_H
#define MS_RT_CABI_H

#include "ms_rt/base.h"
#include "ms_rt/desc.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"

/* `ms_kind`. */
enum {
    VALUE_VOID = 0,
    VALUE_BOOL = 1,
    VALUE_INT = 2,
    VALUE_UINT = 3,
    VALUE_FLOAT = 4,
    VALUE_STRING = 5,
    VALUE_BYTES = 6,
    VALUE_OBJECT = 7,
    VALUE_LIST = 8,
    VALUE_FN = 9
};

typedef struct MsValue {
    uint32_t kind;
    union {
        bool b;
        int64_t i;
        uint64_t u;
        double f;
        struct {
            const uint8_t *data;
            size_t len;
        } buf;
        MsObj *object;
    } as;
} MsValue;

/* `ms_list`: what a shim receives for a List[T] argument or result, built on the stack around the list value. */
typedef struct MsListRef {
    MsList *list;
    uint64_t elem;
} MsListRef;

_Static_assert(sizeof(MsValue) == 24 && offsetof(MsValue, as) == 8, "ms_value layout is ABI");
_Static_assert(sizeof(MsListRef) == 16, "ms_list layout is ABI");


char *ms_str_cstring_v1(const MsStr *s);
void ms_string_new_v1(const uint8_t *data, size_t len, MsStr *out);
void ms_bytes_new_v1(const uint8_t *data, size_t len, MsList *out);
void ms_value_free_v1(MsValue *value);
size_t ms_list_len_v1(const MsListRef *list);
uint32_t ms_list_kind_v1(const MsListRef *list);
MsValue ms_list_get_v1(const MsListRef *list, size_t index);
void ms_list_push_v1(MsListRef *list, const MsValue *value);
MsObj *ms_object_new_v1(size_t size, void (*drop)(void *payload));
void *ms_payload_v1(MsObj *object);
MsObj *ms_object_clone_v1(MsObj *object);
void ms_object_drop_v1(MsObj *object);
MS_NORETURN void ms_fault_v1(const char *text, size_t len);
void ms_call_v1(MsObj *function, const MsValue *args, size_t count, MsValue *result);
MsObj *ms_fn_clone_v1(MsObj *function);
void ms_fn_drop_v1(MsObj *function);
void *ms_on_stop_v1(void (*function)(void *argument), void *argument);
void ms_on_stop_remove_v1(void *hook);

/* Runs every stop hook, once per stop request, from a signal handler or the console control thread. */
void ms_stop_hooks_run(void);

/* The function value generated code passes for a function argument of a user extern: `closure`, which the value
 * owns, takes its arguments from 24-byte cells and leaves its result in the cell after the last parameter; `sig`
 * packs the parameter count in its low byte, then one byte per parameter and the result in the top byte, each
 * `kind | width << 4`. */
/* ms-sig: msrt_fn_new(closure: *mut Obj, sig: u64) -> *mut Obj @keeps:closure */
MsObj *msrt_fn_new(MsObj *closure, uint64_t sig);

#endif
