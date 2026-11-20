/* The runtime ABI that the std natives share (crates/ms-rt-abi): strings, byte lists, handles and status codes.
   To move into include/ms_rt.h when the natives are listed in c-symbols.txt. */
#ifndef MS_STD_ABI_H
#define MS_STD_ABI_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef struct { void *ptr; size_t tagged; } msrt_str;
typedef struct { void *ptr; size_t len, cap; } msrt_vec;
typedef struct msrt_obj msrt_obj;
struct msrt_obj {
    msrt_obj *(*clone)(msrt_obj *);
    void (*drop)(msrt_obj *);
};

enum {
    STATUS_OK = 0,
    STATUS_INVALID_INPUT = 1,
    STATUS_LIMIT_EXCEEDED = 3,
    STATUS_INVALID_DATA = 4,
    STATUS_UNSUPPORTED = 9,
    STATUS_FAILED = 11,
    STATUS_AUTHENTICATION_FAILED = 18
};

extern void *msrt_alloc(size_t size);
extern void msrt_free(void *p);

static inline size_t msrt_str_len(const msrt_str *s) {
    return s->tagged >> 62 == 1 ? (s->tagged >> 56) & 15 : s->tagged & (((size_t)1 << 31) - 1);
}
static inline const char *msrt_str_data(const msrt_str *s) {
    return s->tagged >> 62 == 1 ? (const char *)s : (const char *)s->ptr;
}

/* A Bytes value written as the runtime does: an allocation of exactly len bytes, or null when empty. */
static inline void msrt_write_bytes(msrt_vec *out, const void *data, size_t len) {
    if (len == 0) {
        out->ptr = NULL;
        out->len = out->cap = 0;
        return;
    }
    out->ptr = msrt_alloc(len);
    memcpy(out->ptr, data, len);
    out->len = out->cap = len;
}
#endif
