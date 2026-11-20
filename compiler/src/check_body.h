/* The body checker's context and entry points, shared by the files that check one construct each
 * (check_body.c, check_match.c). A construct a file does not handle calls `ms_body_unsupported`,
 * which leaves the whole function to the Rust checker and undoes what it wrote. */
#ifndef MS_CHECK_BODY_H
#define MS_CHECK_BODY_H

#include "ms/check.h"
#include "ms/constfold.h"
#include "ms/facts.h"
#include "ms/methods.h"

typedef struct MsBody {
    MsCheck *c;
    MsModId module;
    MsFacts *facts;
    MsLiteralFacts *literals;
    MsTy int_ty, float_ty, bool_ty, string_ty, void_ty;
    uint32_t lambda_floor;  /* bindings below this id belong to an enclosing function: captured */
    MsMethodTable *methods; /* the program's methods and interface operations; NULL when not built */
    MsTy invalid_ty;        /* the type of an expression that already drew a diagnostic */
    bool has_close;         /* the module declares a method named `close` */
    MsTy result;
    uint32_t first_binding; /* the bindings from here on belong to the function being checked */
    uint32_t function;      /* the declaration node of the function being checked */
    bool *closed;           /* by binding id: its block ended, so the name is free again */
    uint32_t loop_depth;    /* loops around the statement being checked */
    uint32_t breaks;        /* `break`s seen for the innermost loop */
    MsBuf written;          /* expression ids whose type this function wrote, to undo them */
    MsBuf diags;            /* MsCheckDiag of the function being checked, reported once it is claimed */
    const char *context;    /* what the next `ms_body_expr` value is for ("the return value"), or NULL */
    bool supported;         /* false once a construct outside the handled set is met */
} MsBody;

/* A parameter or local of this type can be called and passed around (check_closure.c). */
bool ms_body_is_function_value(const MsBody *b, MsTy ty);
/* `callee(args)` through the function-typed binding `binding`. */
MsTy ms_body_call_value(MsBody *b, const MsExpr *e, uint32_t binding);
/* A module function named as a value; an anonymous function. */
MsTy ms_body_function_name(MsBody *b, const MsExpr *e);
MsTy ms_body_lambda(MsBody *b, const MsExpr *e, MsTy expected);
/* The primitive type a written annotation names, or MS_TY_NONE after giving up. */
MsTy ms_body_annotation(MsBody *b, const MsTypeRef *t);
/* A call `receiver.name(args)` (check_method.c). */
MsTy ms_body_method_call(MsBody *b, const MsExpr *e);
/* Gives up on the function; the caller returns MS_TY_NONE up the tree. */
MsTy ms_body_unsupported(MsBody *b);
/* Records the type of expression node `node` and returns it. */
MsTy ms_body_record(MsBody *b, uint32_t node, MsTy ty);
/* The type of `e` where `expected` is what the context wants (MS_TY_NONE for no expectation); a
 * different type is a diagnostic, so it gives up. */
MsTy ms_body_expr(MsBody *b, const MsExpr *e, MsTy expected);
/* Checks the statements of a nested scope; whether control falls out of its end. Names bound
 * inside are free again afterwards. */
bool ms_body_block(MsBody *b, const MsStmts *body);
/* Checks the statements of a scope, then `value` in that same scope against `expected`, then
 * closes the scope: the shape of a `match` arm. The value's type, or MS_TY_NONE after giving up. */
MsTy ms_body_block_value(MsBody *b, const MsStmts *body, const MsExpr *value, MsTy expected);
/* Binds a name in the current scope; MS_NONE (and gives up) when the name is already visible. */
uint32_t ms_body_bind(MsBody *b, MsSym name, MsTy ty, uint32_t node, MsPos pos, uint8_t flags, MsBindRole role);
/* The visible binding of `name`, or MS_NONE. */
uint32_t ms_body_find_binding(const MsBody *b, MsSym name);
/* A `match` over an enum or `Optional` scrutinee of type `ty` (check_alt.c). */
/* Whether `ty` is an `Optional`, and its payload type (check_alt.c). */
bool ms_body_optional_payload(const MsBody *b, MsTy ty, MsTy *payload);
MsTy ms_body_match_alternative(MsBody *b, const MsExpr *e, MsTy expected, MsTy ty);
/* A `match` expression (check_match.c). */
MsTy ms_body_match(MsBody *b, const MsExpr *e, MsTy expected);

#endif
