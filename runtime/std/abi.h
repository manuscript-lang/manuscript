/* What the std natives share: the runtime's string, byte list and object header (ms_rt headers), status codes and the
   allocator. */
#ifndef MS_STD_ABI_H
#define MS_STD_ABI_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "ms_rt/string.h"

enum {
    STATUS_OK = 0,
    STATUS_INVALID_INPUT = 1,
    STATUS_LIMIT_EXCEEDED = 3,
    STATUS_INVALID_DATA = 4,
    STATUS_UNSUPPORTED = 9,
    STATUS_FAILED = 11,
    STATUS_AUTHENTICATION_FAILED = 18
};

#include "ms_rt/alloc.h"

/* The runtime's list functions (compiler-emitted descriptors say how an element is stored); msrt_desc_int is the
   descriptor of List[Int]. */
extern const unsigned char msrt_desc_int[];
void msrt_list_with_capacity(const void *desc, int64_t cap, ms_vec *out);
void msrt_list_push(ms_vec *v, const void *desc, const void *elem);
void msrt_list_drop(ms_vec *v, const void *desc);

static inline size_t msrt_str_len(const ms_str *s) { return ms_str_len(s); }
static inline const char *msrt_str_data(const ms_str *s) { return (const char *)ms_str_data(s); }

/* A Bytes value written as the runtime does: an allocation of exactly len bytes, or null when empty. */
static inline void msrt_write_bytes(ms_vec *out, const void *data, size_t len) {
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
