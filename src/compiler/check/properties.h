/* compiler/check/properties.h: the structural properties of a type: Equal, Hashable, Clonable and Data.
 *
 * A property follows from a type's shape: a type is Equal when its parts are, Hashable when it is Equal with
 * hashable parts and holds no resource, Clonable when it holds no resource or function, Data when it holds no
 * resource, function, interface value or runtime handle. A type's own `equals`, `hash` or `to_json` decides
 * Equal, Hashable and Data for it, and a bundled type vouches for Data and Clonable with a `// ms: data` or
 * `// ms: clonable` comment above its declaration. A recursive type is assumed to have the property while its own
 * check is open (Hashable needs an acyclic shape). */
#ifndef MS_COMPILER_CHECK_PROPERTIES_H
#define MS_COMPILER_CHECK_PROPERTIES_H

#include "compiler/check/methods.h"

typedef enum MsProperty { MS_PROPERTY_EQUAL, MS_PROPERTY_HASHABLE, MS_PROPERTY_CLONABLE, MS_PROPERTY_DATA } MsProperty;

/* The property a standard interface names, or false. */
MS_NODISCARD bool ms_property_of_builtin(MsBuiltin builtin, MsProperty *out);

/* The queries in flight and the answers known, kept by the program. */
typedef struct MsPropertyKey {
  MsTy ty;
  uint8_t property;
  bool result;      /* answers only */
  uint32_t methods; /* answers only: the method table the answer was computed against */
} MsPropertyKey;

MS_LIST_DEFINE(MsPropertyKeyList, ms_property_key_list, MsPropertyKey)

/* Whether a type holds a resource, by type id: `stamp` is the method-table size + 1 the answer was computed at. */
typedef struct MsHeld {
  uint32_t stamp;
  bool result;
} MsHeld;

MS_LIST_DEFINE(MsHeldList, ms_held_list, MsHeld)

/* Whether a receiver implements a contract by shape, in an open-addressing table keyed by the pair: `stamp` is the
 * method-table size + 1 the answer was computed at, and 0 marks an empty slot. */
typedef struct MsShapeSlot {
  uint64_t key;
  uint32_t stamp;
  bool result;
} MsShapeSlot;

typedef struct MsPropertyMemo {
  MsShapeSlot *shapes;
  size_t shape_cap; /* a power of two, or 0 */
  size_t shape_len;
  MsHeldList held;
  MsTyList shared_sets; /* native.c: (contract, type set) pairs of the standard interfaces bounded by a type set */
  size_t shared_stamp;  /* the symbol count they were collected at, plus one */
  MsPropertyKeyList active;
  MsPropertyKeyList done;
  MsTy closeable; /* the standard Closeable interface once found */
} MsPropertyMemo;

void ms_property_memo_free(MsPropertyMemo *memo);

/* Whether `ty` has `property`. */
MS_NODISCARD bool ms_check_property(MsCheckProgram *program, MsTy ty, MsProperty property);

/* Whether `ty` is, or holds, a value that must be closed once. */
MS_NODISCARD bool ms_check_closeable(MsCheckProgram *program, MsTy ty);
/* Whether `ty` declares its own `equals(other: Self) Bool` (MS_PROPERTY_EQUAL) or `hash() Int` (MS_PROPERTY_HASHABLE). */
MS_NODISCARD bool ms_check_decided_by_method(MsCheckProgram *program, MsTy ty, MsProperty property);

/* Whether `ty` is, or holds anywhere in its arguments, fields or cases, a closeable value. */
MS_NODISCARD bool ms_check_holds_resource(MsCheckProgram *program, MsTy ty);

/* The definition of a nominal type, or NULL, and one of its field types as `ty` has it. */
const MsDef *ms_check_def_of(const MsCheckProgram *program, MsTy ty);
MsTy ms_check_part_type(MsCheckProgram *program, MsTy ty, const MsDef *def, MsTy field);

typedef enum MsDataReason {
  MS_DATA_RESOURCE,
  MS_DATA_FUNCTION,
  MS_DATA_INTERFACE,
  MS_DATA_HANDLE,
  MS_DATA_UNBOUNDED,
  MS_DATA_COLLECTION,
  MS_DATA_NEVER,
  MS_DATA_OPAQUE
} MsDataReason;

/* The first part of `ty` that keeps it from being Data: false when it is plain data. `path` receives the field
 * path that reaches the part (`a.b`), `*part` the part's type. */
MS_NODISCARD bool ms_check_data_blocker(MsCheckProgram *program, MsTy ty, MsStrBuild *path, MsDataReason *reason,
                                        MsTy *part);

/* The diagnostic for a failed Data bound on `ty`. */
void ms_check_data_message(const MsCheckProgram *program, MsTy ty, MsDataReason reason, MsTy part, MsSpan path,
                           MsStrBuild *out);

/* Whether `def` is declared `opaque`. */
bool ms_check_def_opaque(const MsCheckProgram *program, const MsDef *def);

/* Whether `ty` is a record with a field written `&T`: a value of it looks at what its fields were built from. */
bool ms_check_look_record(const MsCheckProgram *program, MsTy ty);

#endif
