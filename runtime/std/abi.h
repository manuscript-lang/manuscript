/* What the std natives share: the runtime's string, byte list and object header (ms_rt headers), status codes and the
   allocator. */
#ifndef MS_STD_ABI_H
#define MS_STD_ABI_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "ms_rt/safe.h"
#include "ms_rt/string.h"

enum {
    STATUS_OK = 0,
    STATUS_INVALID_INPUT = 1,
    STATUS_OUT_OF_RANGE = 2,
    STATUS_LIMIT_EXCEEDED = 3,
    STATUS_INVALID_DATA = 4,
    STATUS_NOT_FOUND = 5,
    STATUS_ALREADY_EXISTS = 6,
    STATUS_NOT_EMPTY = 7,
    STATUS_PERMISSION_DENIED = 8,
    STATUS_UNSUPPORTED = 9,
    STATUS_CLOSED = 10,
    STATUS_FAILED = 11,
    STATUS_UNAVAILABLE = 12,
    STATUS_TIMED_OUT = 13, /* not STATUS_TIMEOUT: winnt.h defines that macro */
    STATUS_OUTPUT_LIMIT = 14,
    STATUS_NOT_TERMINAL = 15,
    STATUS_NONE = 16,
    STATUS_BUSY = 17,
    STATUS_AUTHENTICATION_FAILED = 18
};

#include "ms_rt/alloc.h"

/* A slot descriptor (crates/ms-rt-abi TypeDesc): the compiler and the runtime read one per element type. A record a
 * native returns in a list is described by a KIND_CUSTOM one with a drop and a deep copy. */
typedef struct MsTypeDesc MsTypeDesc;
struct MsTypeDesc {
    uint32_t size;
    uint32_t align;
    uint32_t kind;
    uint32_t reserved;
    const MsTypeDesc *inner0;
    const MsTypeDesc *inner1;
    void (*drop)(const uint8_t *slot);
    void (*copy)(const uint8_t *source, uint8_t *destination);
    void *eq;
    void *hash;
};

#define MS_TYPE_KIND_STRING 3u
#define MS_TYPE_KIND_LIST 7u
#define MS_TYPE_KIND_CUSTOM 10u

/* The builtin descriptors of an Int and of a String element. */
extern const MsTypeDesc msrt_desc_int;
extern const MsTypeDesc msrt_desc_string;
extern const MsTypeDesc msrt_desc_bytes;

/* The runtime's list functions: a descriptor says how an element is stored. Push takes ownership of the element. */
void msrt_list_with_capacity(const MsTypeDesc *desc, int64_t cap, MsVec *out);
void msrt_list_push(MsVec *v, const MsTypeDesc *desc, const void *elem);
void msrt_list_drop(MsVec *v, const MsTypeDesc *desc);

/* A map is built through its functions and handed over whole: natives never read its slots (runtime/core/map.c).
 * `add` takes ownership of the key and the value slot. */
typedef struct MsMap MsMap;
void msrt_map_new(MsMap *out);
void msrt_map_add(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);
const uint8_t *msrt_map_get_ptr(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
void msrt_map_drop(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd);

static inline size_t msrt_str_len(const MsStr *s) { return ms_str_len(s); }
static inline const char *msrt_str_data(const MsStr *s) { return (const char *)ms_str_data(s); }
/* The bytes of a string, borrowed for as long as the string lives. */
static inline MsBytes msrt_str_bytes(const MsStr *s) { return ms_bytes_of(ms_str_data(s), ms_str_len(s)); }

/* A Bytes value written as the runtime does: an allocation of exactly len bytes, or null when empty. */
static inline void msrt_write_bytes(MsVec *out, const void *data, size_t len) {
    if (len == 0) {
        out->ptr = NULL;
        out->len = out->cap = 0;
        return;
    }
    out->ptr = msrt_alloc(len);
    memcpy(out->ptr, data, len);
    out->len = out->cap = len;
}

/* The start-up records of the startup code (crates/ms-rt/src/start.rs): the arguments the process was started with and
 * the monotonic time it started at (0 before start). */
void msrt_argv(MsVec *out);
int64_t msrt_start_nanos(void);
#endif
