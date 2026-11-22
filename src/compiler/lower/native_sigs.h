/* compiler/lower/native_sigs.h: the C parameters of the runtime's `msrt_` natives, generated from the `ms-sig:`
 * comments of src/runtime (cmake/EmbedNativeSigs.cmake). A bodiless standard operation is called with the values
 * the source gives it; the signature says where the runtime also wants the element, key or value descriptors of
 * the collection and which trailing parameter is the result. */
#ifndef MS_COMPILER_LOWER_NATIVE_SIGS_H
#define MS_COMPILER_LOWER_NATIVE_SIGS_H

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
  NS_VALUE_DESC /* the descriptor of the one value the call moves in or takes out (`ValueDesc`) */
};

enum { NS_MAX_PARAMS = 24 };

typedef struct MsNativeSig {
  const char *name;
  uint8_t count;
  uint8_t kinds[NS_MAX_PARAMS];
  const char *method; /* `Type.operation` when the runtime name differs from `msrt_<type>_<operation>`, else NULL */
  const char *domain; /* what a failure names (`filesystem`), or NULL */
  bool status;        /* returns a u8 */
  const char *inline_op; /* `@inline=` the operation lowering writes out as MIR instead of calling the native, else NULL */
} MsNativeSig;

extern const MsNativeSig ms_native_sigs[];
extern const unsigned ms_native_sig_count;

/* The signature of the native called `name`, or NULL. */
const MsNativeSig *ms_native_sig_find(MsSpan name);

/* The native an operation of a type is declared `@method=` for (`List`, `drop`), or NULL. */
const MsNativeSig *ms_native_sig_find_method(MsSpan type, MsSpan operation);

#endif
