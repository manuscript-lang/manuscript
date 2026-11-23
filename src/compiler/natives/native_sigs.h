/* compiler/natives/native_sigs.h: the C parameters of the runtime's `msrt_` natives, generated from the `ms-sig:`
 * comments of src/runtime (cmake/EmbedNativeSigs.cmake). A bodiless standard operation is called with the values
 * the source gives it; the signature says where the runtime also wants the element, key or value descriptors of
 * the collection and which trailing parameter is the result. */
#ifndef MS_COMPILER_NATIVES_NATIVE_SIGS_H
#define MS_COMPILER_NATIVES_NATIVE_SIGS_H

#include <stdbool.h>
#include <stdint.h>

#include "base/safe.h"

enum {
  NS_VALUE,     /* a scalar passed by value */
  NS_VEC_IN,    /* a list or bytes, read */
  NS_VEC_MUT,   /* a list or bytes, written (the receiver, or the result) */
  NS_STR_IN,
  NS_STR_MUT,
  NS_MAP_IN,    /* a map or set, read */
  NS_MAP_MUT,
  NS_ELEM_DESC, /* the descriptor of the first list's or set's element */
  NS_KEY_DESC,  /* of the first map's key (or set's element) */
  NS_VAL_DESC,  /* of the first map's value */
  NS_ADDR_IN,   /* the address of one value, read */
  NS_ADDR_MUT,  /* the address of one value, written */
  NS_OUT_SCALAR, /* the address of a scalar result */
  NS_ERR_SLOT,  /* the address of the string a failing native explains itself in */
  NS_SHAPE,     /* the shape table of the value the call reads or builds (`*const ShapeTable`), not a source operand */
  NS_HAS_RAW,   /* an `Int?` operand passed as two parameters: the presence flag (this one) and the payload */
  NS_VALUE_DESC, /* the descriptor of the one value the call moves in or takes out (`ValueDesc`) */
  NS_TREE_CTOR  /* the address of the constructor thunk of the `JsonValue` the call builds (`TreeCtor`) */
};

enum { NS_MAX_PARAMS = 24 };

typedef struct MsNativeSig {
  const char *name;
  uint8_t count;
  uint8_t kinds[NS_MAX_PARAMS];
  const char *method; /* `Type.operation` when the runtime name differs from `msrt_<type>_<operation>`, else NULL */
  const char *domain; /* what a failure names (`filesystem`), or NULL */
  bool status;        /* returns a u8 */
  const char *inline_op; /* `@inline=` the list or string operation lowering writes out in its own code instead of calling the native, else NULL */
  bool borrows;          /* `@borrows`: the result is a view into an argument, not a fresh owner */
  bool spawns;           /* `@spawns`: starts a task, so the unwind pass covers the program's frames */
} MsNativeSig;

extern const MsNativeSig ms_native_sigs[];
extern const unsigned ms_native_sig_count;

/* The signature of the native called `name`, or NULL. */
const MsNativeSig *ms_native_sig_find(MsSpan name);

/* A native lowering writes out as MIR instead of calling it, from its `ms-op: <native> <operation>` comment; the
 * operations are listed in lower_scalar_ops.c. The comment names no parameter types: lowering sees the operands. */
typedef struct MsNativeOp {
  const char *name;
  const char *op;
} MsNativeOp;

extern const MsNativeOp ms_native_ops[];

/* The operation of the native called `name`, or NULL. */
const char *ms_native_op_find(MsSpan name);

/* How the runtime represents an extern type, from its `ms-repr: <Type> <repr>` comment: `bytes_buffer` (a Bytes buffer)
 * or `inline<N>` (a plain value of N bytes it reads and writes by address). NULL for a type with no comment. */
typedef struct MsNativeRepr {
  const char *type;
  const char *repr;
} MsNativeRepr;

extern const MsNativeRepr ms_native_reprs[];

const char *ms_native_repr_find(MsSpan type);

/* The native an operation of a type is declared `@method=` for (`List`, `drop`), or NULL. */
const MsNativeSig *ms_native_sig_find_method(MsSpan type, MsSpan operation);

#endif
