/* The runtime functions the C lowering can call from their `ms-sig` declaration. The table is
 * generated from the headers' signatures (`cargo xtask symbols`), so no function is named in the
 * compiler: each parameter's role comes from its declared type, and a function whose signature is
 * tagged `@op=<mnemonic>` is exactly that MIR instruction on its arguments. */
#ifndef MS_RT_OPS_H
#define MS_RT_OPS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MS_RT_MAX_PARAMS 8

typedef enum MsRtParam {
    MS_RT_LIST,     /* a list, borrowed */
    MS_RT_LIST_VAR, /* a list by reference: the instruction yields the updated list */
    MS_RT_STR,      /* a string, borrowed */
    MS_RT_DESC,     /* the descriptor of the element type: a `typedesc` before the call */
    MS_RT_ELEMENT,  /* an element the list takes */
    MS_RT_INT,
    MS_RT_FLOAT,
    MS_RT_BOOL,
    MS_RT_OUT_STR,  /* the result, a string, written through a pointer */
    MS_RT_OUT_LIST, /* the result, a list, written through a pointer */
    MS_RT_OTHER     /* anything the lowering does not marshal: a handle, a slot, an error slot */
} MsRtParam;

typedef enum MsRtRet { MS_RT_RET_VOID, MS_RT_RET_INT, MS_RT_RET_FLOAT, MS_RT_RET_BOOL, MS_RT_RET_OTHER } MsRtRet;

typedef struct MsRtFn {
    const char *symbol;
    const char *op; /* the MIR mnemonic, or "" */
    MsRtParam params[MS_RT_MAX_PARAMS];
    uint32_t nparams;
    MsRtRet ret;
    bool leaf;
    bool twinned; /* a borrowing twin exists (`@view_of=` and siblings): the result may be lent */
} MsRtFn;

/* The function named `symbol`, or NULL. */
const MsRtFn *ms_rt_fn_find(const char *symbol, size_t length);

#endif
