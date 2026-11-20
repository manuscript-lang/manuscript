/* What the std natives share: the runtime's string, byte list and object header (ms_rt headers), status codes and the
   allocator. */
#ifndef MS_STD_ABI_H
#define MS_STD_ABI_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "ms_rt/string.h"

typedef ms_str msrt_str;
typedef ms_vec msrt_vec;
typedef ms_obj msrt_obj;

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

static inline size_t msrt_str_len(const msrt_str *s) { return ms_str_len(s); }
static inline const char *msrt_str_data(const msrt_str *s) { return (const char *)ms_str_data(s); }

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
