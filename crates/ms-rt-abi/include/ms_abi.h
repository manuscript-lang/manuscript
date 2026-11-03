/* Generated from crates/ms-rt-abi/src/lib.rs by the `header_is_current` test; do not edit.
 * Regenerate with: MS_UPDATE_HEADER=1 cargo test -p ms-rt-abi header_is_current
 *
 * ms_abi.h: what a C shim behind a Manuscript `extern fn` may use. The signature types and
 * rules are in documentation/core-language/functions/native-functions.md. Call these functions
 * only on the thread that called the shim, while the extern call is running. */
#ifndef MS_ABI_H
#define MS_ABI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#define MS_NORETURN [[noreturn]]
#define MS_STATIC_ASSERT static_assert
#else
#define MS_NORETURN _Noreturn
#define MS_STATIC_ASSERT _Static_assert
#endif

/* ---- 1. Version ---------------------------------------------------------------------- */
/* Every function links under a versioned name (ms_string_new is ms_string_new_v1), so a shim
   built against another version fails to link and names the function it needs. */
#define MS_ABI_VERSION 1
#define ms_str_cstring ms_str_cstring_v1
#define ms_string_new ms_string_new_v1
#define ms_bytes_new ms_bytes_new_v1
#define ms_value_free ms_value_free_v1
#define ms_list_len ms_list_len_v1
#define ms_list_kind ms_list_kind_v1
#define ms_list_get ms_list_get_v1
#define ms_list_push ms_list_push_v1
#define ms_object_new ms_object_new_v1
#define ms_payload ms_payload_v1
#define ms_object_clone ms_object_clone_v1
#define ms_object_drop ms_object_drop_v1
#define ms_fault ms_fault_v1
#define ms_call ms_call_v1
#define ms_fn_clone ms_fn_clone_v1
#define ms_fn_drop ms_fn_drop_v1
#define ms_on_stop ms_on_stop_v1
#define ms_on_stop_remove ms_on_stop_remove_v1

/* ---- 2. Status codes ----------------------------------------------------------------- */
typedef enum ms_status {
    MS_OK = 0, MS_CANCELLED = 1, MS_TIMEOUT = 2, MS_CLOSED = 3, MS_FAULTED = 4,
    MS_WOULD_DEADLOCK = 5, MS_FULL = 6, MS_INVALID = 7
} ms_status;

/* ---- 3. Strings and bytes ------------------------------------------------------------ */
/* String: a borrowed `const ms_str *` argument, or a trailing `ms_str *out` result. */
typedef struct ms_str { void *ptr_word; size_t tagged; } ms_str;
/* Bytes: a borrowed `const ms_bytes *` argument, or a trailing `ms_bytes *out` result. */
typedef struct ms_bytes { uint8_t *ptr; size_t len; size_t cap; } ms_bytes;
MS_STATIC_ASSERT(sizeof(ms_str) == 16, "ms_str is two words");
MS_STATIC_ASSERT(offsetof(ms_str, tagged) == 8, "ms_str layout");
MS_STATIC_ASSERT(sizeof(ms_bytes) == 24, "ms_bytes is three words");

#define MS_STR_INLINE_MAX 15
/* The top two bits of `tagged` are 1 for a string whose bytes are inside the value. */
static inline int ms_str_is_inline(const ms_str *s) { return (s->tagged >> 62) == 1; }
static inline size_t ms_str_len(const ms_str *s) {
    return ms_str_is_inline(s) ? (s->tagged >> 56) & 15 : s->tagged & (((size_t)1 << 62) - 1);
}
/* The bytes: UTF-8, not NUL-terminated. */
static inline const uint8_t *ms_str_data(const ms_str *s) {
    return ms_str_is_inline(s) ? (const uint8_t *)s : (const uint8_t *)s->ptr_word;
}
static inline size_t ms_bytes_len(const ms_bytes *b) { return b->len; }
static inline const uint8_t *ms_bytes_data(const ms_bytes *b) { return b->ptr; }
/* A malloc'd NUL-terminated copy for C APIs that take `const char *`; NULL if the string
   contains a NUL byte. Free it with free(). */
char *ms_str_cstring(const ms_str *s);
/* Replace the string in `out` with a copy of `len` bytes of UTF-8 (other bytes fault). */
void ms_string_new(const uint8_t *data, size_t len, ms_str *out);
/* Replace the bytes in `out` with a copy of `len` bytes. */
void ms_bytes_new(const uint8_t *data, size_t len, ms_bytes *out);

/* ---- 4. Values ----------------------------------------------------------------------- */
typedef struct ms_object ms_object;
typedef struct ms_list ms_list;
typedef enum ms_kind {
    MS_UNIT = 0, MS_BOOL = 1, MS_INT = 2, MS_UINT = 3, MS_FLOAT = 4,
    MS_STRING = 5, MS_BYTES = 6, MS_OBJECT = 7, MS_LIST = 8, MS_FN = 9
} ms_kind;
typedef union ms_value_as {
    bool b; int64_t i; uint64_t u; double f;           /* sized types widen               */
    struct { const uint8_t *data; size_t len; } buf;   /* MS_STRING, MS_BYTES             */
    ms_object *object;
} ms_value_as;
typedef struct ms_value { ms_kind kind; ms_value_as as; } ms_value;
MS_STATIC_ASSERT(sizeof(ms_value) == 24, "ms_value layout");
/* Free the malloc'd copy that a string or bytes value from ms_list_get holds. */
void ms_value_free(ms_value *v);

/* ---- 5. Lists ------------------------------------------------------------------------ */
/* A List[T] argument is a borrowed `const ms_list *`; a List[T] result is a trailing
   `ms_list *out` that starts empty. The list knows its element type: get widens it into an
   ms_value, push checks the kind and the range and faults naming both types. */
size_t   ms_list_len(const ms_list *l);
ms_kind  ms_list_kind(const ms_list *l);
/* Strings and bytes come back as malloc'd copies (ms_value_free); objects are borrowed. */
ms_value ms_list_get(const ms_list *l, size_t i);
/* Appends a copy of `v`; an object is cloned (ms_object_clone). */
void     ms_list_push(ms_list *out, const ms_value *v);

/* ---- 6. Native objects (extern type) ------------------------------------------------- */
/* An extern type value: `size` bytes of zeroed payload, 16-byte aligned, at a stable address,
   with one owner. `drop(payload)`, which may be NULL, runs once when the owner drops it; it may
   free C memory, start a library's asynchronous close and call ms_object_drop, nothing else. */
ms_object *ms_object_new(size_t size, void (*drop)(void *payload));
void      *ms_payload(ms_object *o);
/* An independent copy of an object the shim keeps past the call; a value that cannot be copied
   (an extern type value is one) faults. */
ms_object *ms_object_clone(ms_object *o);
/* Drops an object the shim owns: one it made and did not return, or cloned. */
void       ms_object_drop(ms_object *o);

/* ---- 7. Errors and faults ------------------------------------------------------------ */
/* A fallible extern returns uint8_t: 0 is ok, n is the n-th case of its error type. If any case
   has a `code: Int` field a trailing `int64_t *code_out` follows; if any has `message: String`
   a trailing `ms_str *message_out` follows. Every output arrives holding a valid empty value
   (0, "", an empty list, NULL); the caller reads the fields of the returned case and drops the
   rest. */
/* An unrecoverable error: reported and cleaned up like a Manuscript fault. */
MS_NORETURN void ms_fault(const char *text, size_t len);

/* ---- 8. Calling Manuscript functions ------------------------------------------------- */
/* A function argument (`f: fn(Int) Bool`) is a borrowed `ms_fn *`. Its parameters (at most
   6) are sized numbers, Bool, String, Bytes or extern types; its result one of those
   but an extern type, or Unit. */
typedef struct ms_fn ms_fn;
/* Calls f on this thread with `count` arguments lent to it, as every function value is called:
   a string or bytes is copied in for the call, an object is passed as it is and stays the
   shim's. An integer must have the kind (MS_INT or MS_UINT) and range of its parameter and a
   string must be UTF-8; anything else faults before the call. `result` (may be NULL) receives the value
   as ms_list_get gives it: strings and bytes are malloc'd copies (ms_value_free). A fault in f
   is a fault of the program; ms_call does not return from it. */
void   ms_call(ms_fn *f, const ms_value *args, size_t count, ms_value *result);
/* A copy of f to keep after the extern call returns, and its drop, on the thread that called
   the shim. */
ms_fn *ms_fn_clone(ms_fn *f);
void   ms_fn_drop(ms_fn *f);

/* ---- 10. Stop requests --------------------------------------------------------------- */
typedef struct ms_stop_hook ms_stop_hook;
/* fn(arg) runs when a stop is requested (SIGINT, SIGTERM, Ctrl-C), from a signal handler or
   another thread, so it may only do async-signal-safe work: set a flag, write to a pipe, call
   uv_async_send. Use it to return from a C call that blocks. NULL when 32 hooks are
   set. */
ms_stop_hook *ms_on_stop(void (*fn)(void *arg), void *arg);
void          ms_on_stop_remove(ms_stop_hook *h);

/* Before version 1: the same as ms_string_new on an empty `out`. */
void msrt_string_from_bytes(const uint8_t *ptr, size_t len, ms_str *out);

#ifdef __cplusplus
}
#endif
#endif
