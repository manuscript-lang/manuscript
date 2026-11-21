/* The runtime functions that are one MIR instruction: a native whose runtime function is tagged
 * `@op=<mnemonic>` in its `ms-sig` comment lowers to that instruction on its arguments. The table is
 * generated from the headers' signatures (`cargo xtask symbols`), so no function is named in
 * the compiler. */
#ifndef MS_RT_OPS_H
#define MS_RT_OPS_H

#include <stddef.h>
#include <stdint.h>

#define MS_RT_MAX_PARAMS 8

typedef enum MsRtParam {
    MS_RT_LIST,     /* a list, borrowed */
    MS_RT_LIST_VAR, /* a list by reference: the instruction yields the updated list */
    MS_RT_DESC,     /* the descriptor of the element type: a `typedesc` before the instruction */
    MS_RT_VALUE     /* an argument value */
} MsRtParam;

typedef struct MsRtOp {
    const char *symbol;
    const char *op; /* the MIR mnemonic */
    MsRtParam params[MS_RT_MAX_PARAMS];
    uint32_t nparams;
} MsRtOp;

/* The tagged function named `symbol`, or NULL. */
const MsRtOp *ms_rt_op_find(const char *symbol, size_t length);

#endif
