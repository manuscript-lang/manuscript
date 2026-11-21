/* The runtime functions the C lowering can call from their `ms-sig` declaration. The table is
 * generated from the headers' signatures (`ms run tools/ms/symbols.ms`), so no function is named in the
 * compiler: each parameter's role comes from its declared type, and a function whose signature is
 * tagged `@op=<mnemonic>` is exactly that MIR instruction on its arguments, and one tagged `@seq=` is the short
 * instruction sequence the tag lists. */
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
    MS_RT_MAP,      /* a map, borrowed */
    MS_RT_KEY_DESC, /* the descriptor of a map's key type */
    MS_RT_VAL_DESC, /* the descriptor of a map's value type */
    MS_RT_KEY_REF,  /* a key passed by address: stored in a slot the call borrows */
    MS_RT_HANDLE,   /* `handle x: *const ObjCell<T>`: a runtime object, borrowed */
    MS_RT_OUT_HANDLE, /* `out: *mut *mut ObjCell<T>`: the runtime object the call creates, written through a pointer */
    MS_RT_OUT_SCALAR, /* `out: *mut i64|f64|u8`: an Int, Float or Bool the call writes through a pointer */
    MS_RT_ERR,      /* the trailing `ErrSlot`: a string the call writes the failure text to */
    MS_RT_HAS,      /* `HasRaw`: an optional scalar crosses as `has, value`; the next parameter is the value and takes no argument */
    MS_RT_OTHER     /* anything the lowering does not marshal: a handle, a slot, an error slot */
} MsRtParam;

typedef enum MsRtRet { MS_RT_RET_VOID, MS_RT_RET_INT, MS_RT_RET_FLOAT, MS_RT_RET_BOOL, MS_RT_RET_OTHER } MsRtRet;

typedef struct MsRtFn {
    const char *symbol;
    const char *op;        /* the MIR mnemonic, or "" */
    const char *word_twin; /* its specialisation for a one-word key over a one-word value, or "" */
    const char *text_twin; /* its specialisation for a String key over a one-word value, or "" */
    const char *seq;       /* `@seq=`: a short MIR instruction sequence over the arguments, or "" (see lower_native.c) */
    int64_t imm;
    uint32_t nparams;
    MsRtRet ret;
    MsRtParam params[MS_RT_MAX_PARAMS];
    bool leaf;
    bool twinned; /* a borrowing twin exists (`@view_of=` and siblings): the result may be lent */
    bool pure;    /* only reads memory and cannot fault (`@pure`) */
    bool fresh;   /* `@fresh`: the result is a new value, never a reference into an argument */
    bool has_imm; /* `@imm=<n>`: the `@op=` instruction carries the integer `imm` */
    const char *domain; /* `@domain=`: how its failures name their module ("network"), or "" */
} MsRtFn;

/* Whether `fn` reports failure by a status the caller turns into a `Result` (see lower_extern.c). */
static inline bool ms_rt_has_err_slot(const MsRtFn *fn) {
    return fn->nparams > 0 && fn->params[fn->nparams - 1] == MS_RT_ERR;
}

/* One row of a native's status table: the error `kind` (`ENOENT`) and the message `words` of a nonzero `status`;
 * words `-` mean the native's own text is the whole message. */
typedef struct MsStatusRow {
    int64_t status;
    const char *kind;
    const char *words;
} MsStatusRow;
typedef struct MsStatusWords {
    const char *symbol;
    int64_t status;
    const char *words;
} MsStatusWords;

/* The rows of `fn`'s status table in status order, with the words its module words differently (stdlib `// ms: words`);
 * returns the row count and fills `out` up to `cap`. */
size_t ms_rt_status_rows(const MsRtFn *fn, MsStatusRow *out, size_t cap);

/* The function named `symbol`, or NULL. */
const MsRtFn *ms_rt_fn_find(const char *symbol, size_t length);

struct MsCheck;

/* The runtime function that implements `method` of the receiver type `receiver` (`msrt_<type>_<method>`,
 * the type in lower case), or NULL. */
const MsRtFn *ms_rt_method_fn(const struct MsCheck *c, uint32_t receiver, uint32_t method);

#endif
