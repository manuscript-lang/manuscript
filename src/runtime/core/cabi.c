/* The C ABI a user `extern fn` shim calls (crates/ms-rt-abi/include/ms_abi.h): strings, bytes, lists, native objects,
 * Manuscript function values and stop hooks. Every entry point is exported under a versioned name (`ms_string_new_v1`),
 * so a shim built against another version fails to link.
 *
 * These run on the thread that called into the shim. Strings and bytes handed out in an `MsValue` are copies from the C
 * library's malloc, which the shim frees with `ms_value_free` (or free), so it may keep them past the call. */
#include <stdatomic.h>

#include "rt_calls.h"
#include "ms_rt/alloc.h"
#include "ms_rt/bytes.h"
#include "ms_rt/cabi.h"
#include "ms_rt/desc.h"
#include "ms_rt/fmt.h"
#include "ms_rt/list.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"
#include "ms_rt/sys.h"
#include "ms_rt/utf8.h"

/* ---- the values of ms_abi.h ---- */

/* A list element type: the value kind in the low byte, the width in bytes above it (crates/ms-rt-abi ELEM_*). */
#define ELEM(kind, width) ((uint64_t)(kind) | (uint64_t)(width) << 8)
enum {
    ELEM_INT8 = ELEM(VALUE_INT, 1),
    ELEM_INT16 = ELEM(VALUE_INT, 2),
    ELEM_INT32 = ELEM(VALUE_INT, 4),
    ELEM_INT64 = ELEM(VALUE_INT, 8),
    ELEM_UINT8 = ELEM(VALUE_UINT, 1),
    ELEM_UINT16 = ELEM(VALUE_UINT, 2),
    ELEM_UINT32 = ELEM(VALUE_UINT, 4),
    ELEM_UINT64 = ELEM(VALUE_UINT, 8),
    ELEM_FLOAT32 = ELEM(VALUE_FLOAT, 4),
    ELEM_FLOAT64 = ELEM(VALUE_FLOAT, 8),
    ELEM_BOOL = ELEM(VALUE_BOOL, 1),
    ELEM_STRING = VALUE_STRING,
    ELEM_BYTES = VALUE_BYTES,
    ELEM_OBJECT = VALUE_OBJECT
};

/* A function value from `msrt_fn_new`: the object header, the closure it owns and the signature word. */
enum { FN_CLOSURE_OFFSET = 16, FN_SIG_OFFSET = 24, FN_SIZE = 32, CLOSURE_CODE_OFFSET = 16, CALL_MAX_PARAMS = 6 };

/* A native object (`ms_object_new`): the header, the shim's drop entry, then the 16-byte-aligned payload. */
enum { OBJECT_DROP_OFFSET = 16, OBJECT_PAYLOAD_OFFSET = 32, STOP_HOOKS_MAX = 32 };

typedef void (*PayloadDrop)(void *payload);
/* The closure code of a function value: takes its arguments from 24-byte cells and leaves its result in the cell
 * after the last parameter. */
typedef void (*ClosureCode)(uint8_t *closure, uint8_t *cells);

/* ---- fault messages ---- */

/* A fault message under construction. The longest is well under the buffer; anything longer is cut. */
typedef struct Message {
    char text[192];
    size_t length;
} Message;

static void message_text(Message *message, const char *text) {
    for (; *text != '\0' && message->length < sizeof message->text; text++) {
        message->text[message->length++] = *text;
    }
}

static void message_unsigned(Message *message, uint64_t value) {
    uint8_t digits[MS_FMT_INTEGER_CAPACITY];
    size_t count = 0;
    if (msrt_fmt_u64(value, digits, sizeof digits, &count)) {
        for (size_t i = 0; i < count && message->length < sizeof message->text; i++) {
            message->text[message->length++] = (char)digits[i];
        }
    }
}

static void message_signed(Message *message, int64_t value) {
    if (value < 0) {
        message_text(message, "-");
        message_unsigned(message, 0 - (uint64_t)value);
    } else {
        message_unsigned(message, (uint64_t)value);
    }
}

MS_NORETURN static void message_fault(const Message *message) { msrt_fault((const uint8_t *)message->text, message->length); }

/* ---- element types ---- */

/* The Manuscript name of a list element type, for fault messages. */
static const char *elem_name(uint64_t elem) {
    switch (elem) {
    case ELEM_INT8: return "Int8";
    case ELEM_INT16: return "Int16";
    case ELEM_INT32: return "Int32";
    case ELEM_INT64: return "Int";
    case ELEM_UINT8: return "UInt8";
    case ELEM_UINT16: return "UInt16";
    case ELEM_UINT32: return "UInt32";
    case ELEM_UINT64: return "UInt64";
    case ELEM_FLOAT32: return "Float32";
    case ELEM_FLOAT64: return "Float";
    case ELEM_BOOL: return "Bool";
    case ELEM_STRING: return "String";
    case ELEM_BYTES: return "Bytes";
    case ELEM_OBJECT: return "an extern type";
    default: return "an unknown type";
    }
}

static const char *kind_name(uint32_t kind) {
    switch (kind) {
    case VALUE_VOID: return "MS_VOID";
    case VALUE_BOOL: return "MS_BOOL";
    case VALUE_INT: return "MS_INT";
    case VALUE_UINT: return "MS_UINT";
    case VALUE_FLOAT: return "MS_FLOAT";
    case VALUE_STRING: return "MS_STRING";
    case VALUE_BYTES: return "MS_BYTES";
    case VALUE_OBJECT: return "MS_OBJECT";
    case VALUE_LIST: return "MS_LIST";
    case VALUE_FN: return "MS_FN";
    default: return "an unknown kind";
    }
}

static const MsTypeDesc pod1 = {.size = 1, .align = 1, .kind = MS_KIND_POD};
static const MsTypeDesc pod2 = {.size = 2, .align = 2, .kind = MS_KIND_POD};
static const MsTypeDesc pod4 = {.size = 4, .align = 4, .kind = MS_KIND_POD};
static const MsTypeDesc pod8 = {.size = 8, .align = 8, .kind = MS_KIND_POD};
static const MsTypeDesc object_desc = {.size = 8, .align = 8, .kind = MS_KIND_SHARED};

/* The descriptor of a list element type. */
static const MsTypeDesc *elem_desc(uint64_t elem) {
    switch (elem) {
    case ELEM_STRING: return &msrt_desc_string;
    case ELEM_BYTES: return &msrt_desc_bytes;
    case ELEM_OBJECT: return &object_desc;
    case ELEM_BOOL: return &msrt_desc_bool;
    default: break;
    }
    switch ((elem >> 8) & 0xff) {
    case 1: return &pod1;
    case 2: return &pod2;
    case 4: return &pod4;
    default: return &pod8;
    }
}

static bool signed_fits(int64_t value, uint64_t width) {
    return width >= 8 || (value >= -((int64_t)1 << (width * 8 - 1)) && value < ((int64_t)1 << (width * 8 - 1)));
}

static bool unsigned_fits(uint64_t value, uint64_t width) { return width >= 8 || value < ((uint64_t)1 << (width * 8)); }

/* ---- copies ---- */

/* A malloc copy of `length` bytes (NULL for none); a failure faults, since the shim cannot be told. */
static const uint8_t *system_copy(MsBytes data) {
    if (data.len == 0) {
        return NULL;
    }
    uint8_t *copy = ms_sys_malloc(data.len);
    if (copy == NULL) {
        Message message = {0};
        message_text(&message, "out of memory copying ");
        message_unsigned(&message, data.len);
        message_text(&message, " bytes for a native");
        message_fault(&message);
    }
    __builtin_memcpy(copy, data.ptr, data.len);
    return copy;
}

static MsBytes string_bytes(const MsStr *string) { return ms_bytes_of(ms_str_data(string), ms_str_len(string)); }

static MsBytes vec_bytes(const MsList *bytes) { return ms_bytes_of(bytes->ptr, bytes->len); }

/* Replaces the bytes in `out` with a copy of `data`. */
static void bytes_from(MsBytes data, MsList *out) {
    uint8_t *copy = NULL;
    if (data.len > 0) {
        copy = msrt_alloc(data.len);
        __builtin_memcpy(copy, data.ptr, data.len);
    }
    *out = (MsList){.ptr = copy, .len = data.len, .cap = data.len};
}

/* ---- strings and bytes ---- */

char *ms_str_cstring_v1(const MsStr *s) {
    const MsBytes data = string_bytes(s);
    for (size_t i = 0; i < data.len; i++) {
        if (data.ptr[i] == 0) {
            return NULL;
        }
    }
    char *text = ms_sys_malloc(data.len + 1);
    if (text == NULL) {
        return NULL;
    }
    if (data.len > 0) {
        __builtin_memcpy(text, data.ptr, data.len);
    }
    text[data.len] = '\0';
    return text;
}

void ms_string_new_v1(const uint8_t *data, size_t len, MsStr *out) {
    if (!ms_utf8_is_valid(data, len)) {
        Message message = {0};
        message_text(&message, "ms_string_new received ");
        message_unsigned(&message, len);
        message_text(&message, " bytes that are not UTF-8; use ms_bytes_new for binary data");
        message_fault(&message);
    }
    ms_str_release(out);
    msrt_string_from_bytes(data, len, out);
}

void ms_bytes_new_v1(const uint8_t *data, size_t len, MsList *out) {
    msrt_bytes_drop(out);
    bytes_from(ms_bytes_of(data, len), out);
}

void ms_value_free_v1(MsValue *value) {
    if (value->kind == VALUE_STRING || value->kind == VALUE_BYTES) {
        void *owned = NULL;
        __builtin_memcpy(&owned, &value->as.buf.data, sizeof owned);
        ms_sys_free(owned);
    }
    value->kind = VALUE_VOID;
    value->as.u = 0;
}

/* ---- lists ---- */

size_t ms_list_len_v1(const MsListRef *list) { return list->list->len; }

uint32_t ms_list_kind_v1(const MsListRef *list) { return (uint32_t)(list->elem & 0xff); }

/* The value of the element of type `elem` at `at`: integers widened, strings and bytes malloc copies, objects
 * borrowed. */
static MsValue load_value(const uint8_t *at, uint64_t elem) {
    MsValue value = {.kind = (uint32_t)(elem & 0xff)};
    switch (elem) {
    case ELEM_INT8: { value.as.i = (int64_t)((int)*at ^ 0x80) - 0x80; /* sign-extends one byte */ break; }
    case ELEM_INT16: { int16_t v; __builtin_memcpy(&v, at, sizeof v); value.as.i = v; break; }
    case ELEM_INT32: { int32_t v; __builtin_memcpy(&v, at, sizeof v); value.as.i = v; break; }
    case ELEM_INT64: __builtin_memcpy(&value.as.i, at, sizeof value.as.i); break;
    case ELEM_UINT8: value.as.u = *at; break;
    case ELEM_UINT16: { uint16_t v; __builtin_memcpy(&v, at, sizeof v); value.as.u = v; break; }
    case ELEM_UINT32: { uint32_t v; __builtin_memcpy(&v, at, sizeof v); value.as.u = v; break; }
    case ELEM_UINT64: __builtin_memcpy(&value.as.u, at, sizeof value.as.u); break;
    case ELEM_FLOAT32: { float v; __builtin_memcpy(&v, at, sizeof v); value.as.f = (double)v; break; }
    case ELEM_FLOAT64: __builtin_memcpy(&value.as.f, at, sizeof value.as.f); break;
    case ELEM_BOOL: value.as.b = *at != 0; break;
    case ELEM_STRING: {
        MsStr string;
        __builtin_memcpy(&string, at, sizeof string);
        const MsBytes data = string_bytes(&string);
        value.as.buf.data = system_copy(data);
        value.as.buf.len = data.len;
        break;
    }
    case ELEM_BYTES: {
        MsList bytes;
        __builtin_memcpy(&bytes, at, sizeof bytes);
        const MsBytes data = vec_bytes(&bytes);
        value.as.buf.data = system_copy(data);
        value.as.buf.len = data.len;
        break;
    }
    default: __builtin_memcpy(&value.as.object, at, sizeof(void *)); break;
    }
    return value;
}

MsValue ms_list_get_v1(const MsListRef *list, size_t index) {
    const MsList *items = list->list;
    if (index >= items->len) {
        Message message = {0};
        message_text(&message, "ms_list_get index ");
        message_unsigned(&message, index);
        message_text(&message, " is out of range for a list of ");
        message_unsigned(&message, items->len);
        message_text(&message, " elements");
        message_fault(&message);
    }
    return load_value(items->ptr + index * elem_desc(list->elem)->size, list->elem);
}

/* Why an MsValue cannot become a value of an element type. */
typedef enum Mismatch { MATCH_OK, MATCH_KIND, MATCH_RANGE, MATCH_UTF8, MATCH_NULL } Mismatch;

static Mismatch mismatch(const MsValue *value, uint64_t elem) {
    if (value->kind != (elem & 0xff)) {
        return MATCH_KIND;
    }
    const uint64_t width = (elem >> 8) & 0xff;
    switch (value->kind) {
    case VALUE_INT: return signed_fits(value->as.i, width) ? MATCH_OK : MATCH_RANGE;
    case VALUE_UINT: return unsigned_fits(value->as.u, width) ? MATCH_OK : MATCH_RANGE;
    case VALUE_STRING: return ms_utf8_is_valid(value->as.buf.data, value->as.buf.len) ? MATCH_OK : MATCH_UTF8;
    case VALUE_OBJECT: return value->as.object != NULL ? MATCH_OK : MATCH_NULL;
    default: return MATCH_OK;
    }
}

/* The start of a mismatch fault: "received MS_STRING", "value 300 is out of range". */
static void message_mismatch(Message *message, Mismatch why, const MsValue *value) {
    switch (why) {
    case MATCH_KIND:
        message_text(message, "received ");
        message_text(message, kind_name(value->kind));
        break;
    case MATCH_RANGE:
        message_text(message, "value ");
        if (value->kind == VALUE_INT) {
            message_signed(message, value->as.i);
        } else {
            message_unsigned(message, value->as.u);
        }
        message_text(message, " is out of range");
        break;
    case MATCH_UTF8:
        message_text(message, "received ");
        message_unsigned(message, value->as.buf.len);
        message_text(message, " bytes that are not UTF-8");
        break;
    case MATCH_NULL: message_text(message, "received a NULL object"); break;
    case MATCH_OK: break;
    }
}

/* Writes at `at` (24 bytes suffice) the value of type `elem` that `value` makes, which `mismatch` accepted: a string
 * or bytes copy, the number, and an object cloned when its new holder owns it (a list element) or the object itself
 * when it is only lent (an argument of ms_call). */
static void store_value(const MsValue *value, uint64_t elem, uint8_t *at, bool owned) {
    switch (elem) {
    case ELEM_FLOAT32: {
        const float f = (float)value->as.f;
        __builtin_memcpy(at, &f, sizeof f);
        break;
    }
    case ELEM_FLOAT64: __builtin_memcpy(at, &value->as.f, sizeof value->as.f); break;
    case ELEM_BOOL: *at = value->as.b ? 1 : 0; break;
    case ELEM_STRING: {
        MsStr string;
        msrt_string_from_bytes(value->as.buf.data, value->as.buf.len, &string);
        __builtin_memcpy(at, &string, sizeof string);
        break;
    }
    case ELEM_BYTES: {
        MsList bytes;
        bytes_from(ms_bytes_of(value->as.buf.data, value->as.buf.len), &bytes);
        __builtin_memcpy(at, &bytes, sizeof bytes);
        break;
    }
    case ELEM_OBJECT: {
        MsObj *object = owned ? msrt_obj_clone(value->as.object) : value->as.object;
        __builtin_memcpy(at, &object, sizeof(void *));
        break;
    }
    default: __builtin_memcpy(at, &value->as.u, sizeof value->as.u); break; /* integers: the low bytes of the word */
    }
}

void ms_list_push_v1(MsListRef *list, const MsValue *value) {
    const Mismatch why = mismatch(value, list->elem);
    if (why != MATCH_OK) {
        Message message = {0};
        message_text(&message, "ms_list_push ");
        message_mismatch(&message, why, value);
        message_text(&message, " for a List[");
        message_text(&message, elem_name(list->elem));
        message_text(&message, "]");
        message_fault(&message);
    }
    uint64_t slot[3] = {0};
    store_value(value, list->elem, (uint8_t *)slot, true);
    msrt_list_push(list->list, elem_desc(list->elem), (const uint8_t *)slot);
}

/* ---- native objects ---- */

static void native_object_drop(MsObj *object) {
    uint8_t *base = (uint8_t *)object;
    PayloadDrop drop = NULL;
    __builtin_memcpy(&drop, base + OBJECT_DROP_OFFSET, sizeof drop);
    if (drop != NULL) {
        drop(base + OBJECT_PAYLOAD_OFFSET);
    }
    msrt_free(base);
}

MsObj *ms_object_new_v1(size_t size, PayloadDrop drop) {
    size_t total = 0;
    if (!ms_size_add(OBJECT_PAYLOAD_OFFSET, size, &total)) {
        Message message = {0};
        message_text(&message, "ms_object_new size ");
        message_unsigned(&message, size);
        message_text(&message, " is too large");
        message_fault(&message);
    }
    uint8_t *base = msrt_alloc_zeroed(total);
    MsObj *object = (MsObj *)__builtin_assume_aligned(base, _Alignof(MsObj));
    object->clone = NULL;
    object->drop = native_object_drop;
    __builtin_memcpy(base + OBJECT_DROP_OFFSET, &drop, sizeof drop);
    return object;
}

void *ms_payload_v1(MsObj *object) { return (uint8_t *)object + OBJECT_PAYLOAD_OFFSET; }

MsObj *ms_object_clone_v1(MsObj *object) { return msrt_obj_clone(object); }

void ms_object_drop_v1(MsObj *object) { msrt_obj_drop(object); }

void ms_fault_v1(const char *text, size_t len) { msrt_fault((const uint8_t *)text, len); }

/* ---- function values ---- */

static MsObj *load_object(const uint8_t *at) {
    MsObj *object = NULL;
    __builtin_memcpy(&object, at, sizeof(void *));
    return object;
}

static void fn_drop(MsObj *object) {
    uint8_t *base = (uint8_t *)object;
    msrt_obj_drop(load_object(base + FN_CLOSURE_OFFSET));
    msrt_free(base);
}

static uint64_t load_word(const uint8_t *at) {
    uint64_t word = 0;
    __builtin_memcpy(&word, at, sizeof word);
    return word;
}

/* A new function value over a clone of the closure. */
static MsObj *fn_clone(MsObj *object) {
    const uint8_t *base = (const uint8_t *)object;
    return msrt_fn_new(msrt_obj_clone(load_object(base + FN_CLOSURE_OFFSET)), load_word(base + FN_SIG_OFFSET));
}

MsObj *msrt_fn_new(MsObj *closure, uint64_t sig) {
    uint8_t *base = msrt_alloc_zeroed(FN_SIZE);
    MsObj *object = (MsObj *)__builtin_assume_aligned(base, _Alignof(MsObj));
    object->clone = fn_clone;
    object->drop = fn_drop;
    __builtin_memcpy(base + FN_CLOSURE_OFFSET, &closure, sizeof(void *));
    __builtin_memcpy(base + FN_SIG_OFFSET, &sig, sizeof sig);
    return object;
}

/* The element code of one signature byte: the kind in its low four bits, the width above them. */
static uint64_t sig_elem(uint64_t byte) { return (byte & 0xf) | (byte >> 4) << 8; }

void ms_call_v1(MsObj *function, const MsValue *args, size_t count, MsValue *result) {
    const uint8_t *base = (const uint8_t *)function;
    const uint64_t sig = load_word(base + FN_SIG_OFFSET);
    const size_t parameters = (size_t)(sig & 0xff);
    if (count != parameters) {
        Message message = {0};
        message_text(&message, "ms_call received ");
        message_unsigned(&message, count);
        message_text(&message, " arguments for a function of ");
        message_unsigned(&message, parameters);
        message_text(&message, " parameters");
        message_fault(&message);
    }
    uint64_t elems[CALL_MAX_PARAMS] = {0};
    for (size_t i = 0; i < parameters && i < CALL_MAX_PARAMS; i++) {
        elems[i] = sig_elem((sig >> (8 * (i + 1))) & 0xff);
        const Mismatch why = mismatch(&args[i], elems[i]);
        if (why != MATCH_OK) {
            Message message = {0};
            message_text(&message, "ms_call ");
            message_mismatch(&message, why, &args[i]);
            message_text(&message, " for parameter ");
            message_unsigned(&message, i + 1);
            message_text(&message, " of type ");
            message_text(&message, elem_name(elems[i]));
            message_fault(&message);
        }
    }
    uint64_t cells[CALL_MAX_PARAMS + 1][3] = {{0}};
    for (size_t i = 0; i < parameters && i < CALL_MAX_PARAMS; i++) {
        store_value(&args[i], elems[i], (uint8_t *)cells[i], false);
    }
    uint8_t *closure = (uint8_t *)load_object(base + FN_CLOSURE_OFFSET);
    ClosureCode code = NULL;
    __builtin_memcpy(&code, closure + CLOSURE_CODE_OFFSET, sizeof code);
    /* The thunk takes the string and bytes copies out of their cells and drops them; an object stays the shim's. */
    code(closure, (uint8_t *)cells);

    const uint64_t returned = sig >> 56;
    MsValue value = {.kind = VALUE_VOID};
    if (returned != 0) {
        uint8_t *at = (uint8_t *)cells[CALL_MAX_PARAMS];
        const uint64_t elem = sig_elem(returned);
        value = load_value(at, elem);
        if (elem == ELEM_STRING) {
            MsStr string;
            __builtin_memcpy(&string, at, sizeof string);
            ms_str_release(&string);
        } else if (elem == ELEM_BYTES) {
            MsList bytes;
            __builtin_memcpy(&bytes, at, sizeof bytes);
            msrt_bytes_drop(&bytes);
        }
    }
    if (result == NULL) {
        ms_value_free_v1(&value);
    } else {
        *result = value;
    }
}

MsObj *ms_fn_clone_v1(MsObj *function) { return msrt_obj_clone(function); }

void ms_fn_drop_v1(MsObj *function) { msrt_obj_drop(function); }

/* ---- stop hooks ---- */

/* A hook slot: a function (NULL when free, FILLING while `ms_on_stop` fills it) and its argument. A signal handler
 * reads them, so they are atomics written in order. */
typedef void (*StopFn)(void *argument);
typedef struct StopHook {
    _Atomic(StopFn) function;
    _Atomic(void *) argument;
} StopHook;

static void filling_marker(void *argument) { (void)argument; }
#define FILLING filling_marker

static StopHook stop_hooks[STOP_HOOKS_MAX];

void ms_stop_hooks_run(void) {
    for (size_t i = 0; i < STOP_HOOKS_MAX; i++) {
        const StopFn function = atomic_load_explicit(&stop_hooks[i].function, memory_order_acquire);
        if (function != NULL && function != FILLING) {
            function(atomic_load_explicit(&stop_hooks[i].argument, memory_order_relaxed));
        }
    }
}

void *ms_on_stop_v1(StopFn function, void *argument) {
    for (size_t i = 0; i < STOP_HOOKS_MAX; i++) {
        /* Claim a free slot with a placeholder, publish the argument, then the function. */
        StopFn expected = NULL;
        if (atomic_compare_exchange_strong_explicit(&stop_hooks[i].function, &expected, FILLING, memory_order_acquire,
                                                    memory_order_relaxed)) {
            atomic_store_explicit(&stop_hooks[i].argument, argument, memory_order_relaxed);
            atomic_store_explicit(&stop_hooks[i].function, function, memory_order_release);
            return &stop_hooks[i];
        }
    }
    return NULL;
}

void ms_on_stop_remove_v1(void *hook) {
    for (size_t i = 0; i < STOP_HOOKS_MAX; i++) {
        if (hook == &stop_hooks[i]) {
            atomic_store_explicit(&stop_hooks[i].function, NULL, memory_order_release);
            return;
        }
    }
}
