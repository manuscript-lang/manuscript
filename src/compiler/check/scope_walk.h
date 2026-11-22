/* compiler/check/scope_walk.h: a syntax walk that keeps the lexical scope of bindings.
 *
 * Visits every body of a module in source order and tells the visitor about each name read and each assignment
 * to a plain name, together with the bindings in scope at that point (parameters, `:=` and `var` bindings,
 * pattern names, loop variables, match payloads, lambda parameters, and `self` inside a method). Passes that
 * need to know what a name means (mutability, name resolution) are visitors; the walk itself decides nothing. */
#ifndef MS_COMPILER_CHECK_SCOPE_WALK_H
#define MS_COMPILER_CHECK_SCOPE_WALK_H

#include "compiler/check/program.h"

/* How a binding came to be: a `:=`/`var` local, the name of an `if` narrowing, a match payload, or anything else
 * (parameters, loop variables, `self`). */
typedef enum MsBindingOrigin { MS_BIND_OTHER, MS_BIND_LOCAL, MS_BIND_NARROWED, MS_BIND_PAYLOAD } MsBindingOrigin;

typedef struct MsBinding {
  MsName name;
  MsPos decl;
  bool mutable_;
  bool invalid; /* its type is known to be wrong */
  MsBindingOrigin origin;
} MsBinding;

MS_LIST_DEFINE(MsBindingList, ms_binding_list, MsBinding)

/* Where a visited node sits: the `impl` declaration whose method holds it, or NULL. */
typedef struct MsScopeSite {
  const MsDecl *impl;
  bool in_constant; /* inside the value of a module constant */
} MsScopeSite;

typedef struct MsScopeVisitor {
  void *context;
  /* Whether a parameter's written type is known to be wrong, so a match on it has no meaningful arms; may be
   * NULL. */
  bool (*invalid_param)(void *context, const MsParam *param);
  /* A binding has just come into scope; may be NULL. */
  void (*declared)(void *context, const MsBinding *binding);
  /* A name read: `expr` is a MS_E_NAME. `scope` lists the enclosing bindings, innermost last. */
  void (*name)(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site);
  /* An assignment whose target is a plain name (`stmt->u.assign.name`). */
  void (*assign)(void *context, const MsStmt *stmt, const MsBindingList *scope, const MsScopeSite *site);
} MsScopeVisitor;

/* The binding of `name` in `scope`, or NULL. */
const MsBinding *ms_scope_lookup(const MsBindingList *scope, MsName name);

void ms_scope_walk_module(const MsModule *tree, const MsScopeVisitor *visitor, MsNames *names);

#endif
