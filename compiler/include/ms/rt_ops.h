/* The runtime functions that are one MIR instruction: a native whose runtime function is tagged
 * `@op=<mnemonic>` in its `ms-sig` comment lowers to that instruction on its arguments. The table is
 * generated from the headers' signatures (`cargo xtask symbols`), so no function is named in
 * the compiler. */
#ifndef MS_RT_OPS_H
#define MS_RT_OPS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MS_RT_MAX_PARAMS 8

typedef enum MsRtParam {
    MS_RT_LIST,     /* a list, borrowed */
    MS_RT_LIST_VAR, /* a list by reference: the instruction yields the updated list */
    MS_RT_DESC,     /* the descriptor of the element type: a `typedesc` before the instruction */
    MS_RT_VALUE,    /* an argument value */
    MS_RT_MAP,      /* a map, borrowed */
    MS_RT_KEY_DESC, /* the descriptor of a map's key type */
    MS_RT_VAL_DESC, /* the descriptor of a map's value type */
    MS_RT_KEY_REF,  /* a key passed by address: stored in a slot the call borrows */
    MS_RT_OTHER     /* anything the lowering does not marshal yet: the method is left to Rust */
} MsRtParam;

typedef struct MsRtOp {
    const char *symbol;
    const char *op; /* the MIR mnemonic, or "" when the function is a runtime call */
    MsRtParam params[MS_RT_MAX_PARAMS];
    uint32_t nparams;
    bool pure;             /* only reads memory and cannot fault (`@pure`) */
    const char *word_twin; /* its specialisation for a one-word key over a one-word value, or "" */
    const char *text_twin; /* its specialisation for a String key over a one-word value, or "" */
} MsRtOp;

/* The tagged function named `symbol`, or NULL. */
const MsRtOp *ms_rt_op_find(const char *symbol, size_t length);

#endif
