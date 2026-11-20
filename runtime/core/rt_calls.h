/* rt_calls.h: what runtime/core calls by its exported name and the Rust runtime still defines: faults, objects,
 * strings and the cleanup stack. Each moves to its own C module in turn; the declarations here follow it
 * and the unit tests link runtime/tests/support/rt_stubs.c in place of them.
 *
 * The allocator is C already (ms_rt/alloc.h). Faults do not return: they leave by the runtime's jump.
 */
#ifndef MS_RT_CALLS_H
#define MS_RT_CALLS_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"
#include "ms_rt/desc.h"

/* The family of a fault, which the structured fault record names (crates/ms-rt-abi FaultKind). */
typedef enum MsFaultKind {
    MS_FAULT_GENERIC = 0,
    MS_FAULT_OVERFLOW = 5,
    MS_FAULT_INDEX_OUT_OF_RANGE = 6
} MsFaultKind;

/* Raises a fault of `kind` with the message `msg[0..len]`. */
MS_NORETURN void msfault_raise(uint8_t kind, const uint8_t *msg, size_t len);
/* Raises a generic fault. */
MS_NORETURN void msrt_fault(const uint8_t *msg, size_t len);
/* "index N out of range for length L; pass a default". */
MS_NORETURN void msrt_index_fault(int64_t index, int64_t length);
/* The fault of a list mutator given a bad index: operation 0 insert, 1 remove, 2 set, 3 swap, 4 replace. */
MS_NORETURN void msrt_list_index_fault(int64_t operation, int64_t index, int64_t len);

/* A cleanup runs when a fault or cancellation leaves the code between push and discard by a jump. */
typedef void (*MsCleanupFn)(uint8_t *arg);
size_t msrt_cleanup_push(MsCleanupFn run, uint8_t *arg);
void msrt_cleanup_discard(size_t handle);

/* Objects with a header (closures, handles). Null stays null. */
typedef struct MsObj MsObj;
MsObj *msrt_obj_clone(MsObj *object);
void msrt_obj_drop(MsObj *object);

/* Strings (ms_rt/string.h has equality and hash, which desc.c declares through MsStr): copy and release, which the Rust runtime still defines. */
void msrt_string_clone(const MsStr *s, MsStr *out);
void msrt_string_free(const MsStr *s);
uint8_t msrt_string_eq(const MsStr *a, const MsStr *b);
int64_t msrt_string_hash(const MsStr *s);
void msrt_string_empty(MsStr *out);
void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out);

/* Hash of `len` bytes (the string hash over bytes). */
int64_t msrt_hash_bytes(const uint8_t *ptr, size_t len);

/* Maps and sets, which the slot kinds MS_KIND_MAP and MS_KIND_SET store. Equality has no exported
 * entry yet: `msmap_eq` is glue in crates/ms-rt/src/map.rs until map.c replaces it. */
struct MsMap;
struct MsTypeDesc;
void msrt_map_drop(struct MsMap *m, const struct MsTypeDesc *kd, const struct MsTypeDesc *vd);
void msrt_map_copy(const struct MsMap *m, const struct MsTypeDesc *kd, const struct MsTypeDesc *vd, struct MsMap *out);
void msrt_map_new(struct MsMap *out);
uint8_t msrt_map_contains(const struct MsMap *m, const struct MsTypeDesc *kd, const struct MsTypeDesc *vd, const uint8_t *key);
void msrt_set_add_copy(struct MsMap *m, const struct MsTypeDesc *kd, const uint8_t *key);
uint8_t msmap_eq(const struct MsMap *a, const struct MsMap *b, const struct MsTypeDesc *kd, const struct MsTypeDesc *vd);

#endif
