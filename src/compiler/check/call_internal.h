/* compiler/check/call_internal.h: the call being checked, shared by calls.c and call_report.c. */
#ifndef MS_COMPILER_CHECK_CALL_INTERNAL_H
#define MS_COMPILER_CHECK_CALL_INTERNAL_H

#include "compiler/check/body.h"

typedef struct Target {
  MsRef ref;
  MsTy sig;               /* the function type called, receiver already bound */
  MsTyList vars;          /* owned: the type variables to infer, in declaration order */
  const MsParams *ast;    /* the declared parameters (for defaults), or NULL */
  uint32_t ast_module;
  const MsExpr *receiver; /* the written receiver of a method call */
  uint8_t receiver_flags; /* MS_PARAM_VAR or MS_PARAM_MOVE: how the method takes its receiver */
  MsStrBuild name_text;   /* owned: the callee as written, `values.map` */
  MsSpan name;
  MsTyList explicit_args; /* owned: written type arguments */
  size_t nargs;           /* the written argument count, to choose between methods of one name */
  bool constructor;       /* a type's or case's constructor, or the prelude's ok, error or some: inference failures use its wording */
  MsTy nominal;           /* the type a constructor or case builds, else MS_TY_NONE */
  bool builtin;           /* a built-in type's constructor: its arguments are not matched to declared fields */
} Target;

/* How a written argument was matched. */
typedef enum ArgState { ARG_MATCHED, ARG_EXTRA, ARG_UNKNOWN, ARG_DUPLICATE } ArgState;

typedef struct Matched {
  int32_t *slot;    /* the argument written for each parameter, or -1 */
  uint8_t *state;   /* ArgState of each written argument */
  size_t count;
  const MsTy *bound; /* the type arguments the arguments fixed so far, MS_TY_NONE for the rest; NULL when none */
} Matched;

/* The written name of a parameter: the declaration's, since function types do not keep names in their identity. */
MsName target_param_name(const Body *body, const Target *target, size_t index);

/* Whether a parameter takes no label: a function value's, or one declared positional. */
bool target_positional(const Target *target, size_t index, const MsTyTable *types);

/* Reports the arguments that match no parameter and the parameters left without an argument, and types the
 * unmatched arguments. */
void body_report_arguments(Body *body, const Target *target, const MsExpr *call, const Matched *matched);
bool body_param_omittable(const Body *body, const MsParam *param);

#endif
