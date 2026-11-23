/* compiler/check/instantiate.h: the type arguments of a generic call and the callee's signature under them.
 *
 * Explicit arguments come first, then each call argument is matched against its parameter type, then the
 * expected result type fills what is still open, then defaults. Every variable must end bound and meet its
 * bounds. The caller (expression typing) checks that each argument is assignable to the instantiated
 * parameter; this module only decides the type arguments. */
#ifndef MS_COMPILER_CHECK_INSTANTIATE_H
#define MS_COMPILER_CHECK_INSTANTIATE_H

#include "compiler/check/bounds.h"

typedef struct MsInstance {
  MsTy ty;         /* the callee's function type with the arguments substituted */
  MsTyList args;   /* owned: one type per variable, in declaration order */
  MsString message; /* owned: the diagnostic when instantiation failed, else empty */
  MsTyList unbound; /* owned: the variables no argument or expected type determined, when that is why it failed */
  size_t conflict;  /* the parameter whose argument disagreed with the others, or SIZE_MAX; `args` then holds the types so far */
} MsInstance;

void ms_instance_free(MsInstance *instance);

/* Instantiates `callee` (a function type) whose type variables are `variables[0..nvars)`, named `name` in
 * diagnostics. `explicit_args` are the written type arguments (none, or a prefix of the variables).
 * `arg_tys[i]` is the type of the argument for parameter i (MS_TY_NONE when unknown or erroneous, which
 * constrains nothing); `order` lists the parameters in the order their arguments are written (NULL: parameter
 * order); `expected_result` is the type the call is used as, or MS_TY_NONE. Returns false with
 * `out->message` set when no consistent instantiation exists. */
MS_NODISCARD bool ms_check_instantiate(MsCheckProgram *program, MsTy callee, const MsTy *variables, size_t nvars,
                                       MsSpan name, const MsTy *explicit_args, size_t nexplicit,
                                       const MsTy *arg_tys, size_t nargs, const size_t *order, MsTy expected_result,
                                       MsInstance *out);

#endif
