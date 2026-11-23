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

/* What kind of name a binding is, for diagnostics that name it: a parameter the callee only borrows, a parameter it
 * owns (`move`), a `:=`/`var` local, a loop variable, `self` of a method, or anything else. */
typedef enum MsBindingKind { MS_BK_OTHER, MS_BK_PARAM, MS_BK_OWNED_PARAM, MS_BK_LOCAL, MS_BK_LOOP, MS_BK_SELF } MsBindingKind;

typedef struct MsBinding {
  MsName name;
  MsPos decl;
  bool mutable_;
  bool invalid; /* its type is known to be wrong */
  MsBindingOrigin origin;
  MsBindingKind kind;
  uint32_t anchor; /* where the walk reaches it, when that is later than its position (an `if` binding: after the condition); else 0 */
  uint32_t depth; /* how many blocks, loops, arms and lambdas enclose it inside its function: 0 for parameters */
} MsBinding;

MS_LIST_DEFINE(MsBindingList, ms_binding_list, MsBinding)

/* Where a visited node sits: the `impl` declaration whose method holds it, or NULL. */
typedef struct MsScopeSite {
  const MsDecl *impl;
  const MsDecl *decl; /* the declaration being walked */
  bool in_constant;  /* inside the value of a module constant */
  bool in_constant_call; /* ... and inside a call or lambda there, which the constant rules reject as a whole */
  bool type_reading; /* the name is the value reading of a bracket entry that may be a type */
  const MsExpr *lambda; /* the innermost lambda holding the node, or NULL */
  size_t lambda_scope;  /* the bindings before this index of the scope are captured by that lambda */
} MsScopeSite;

typedef struct MsScopeVisitor {
  void *context;
  /* Whether a parameter's written type is known to be wrong, so a match on it has no meaningful arms; may be
   * NULL. */
  bool (*invalid_param)(void *context, const MsParam *param);
  /* Whether the lone lowercase name of a match arm may name a variant of the matched enum rather than bind an optional
   * payload; such an arm binds nothing. May be NULL. */
  bool (*variant_name)(void *context, MsName name);
  /* A binding has just come into scope, as the last of `scope`; may be NULL. */
  void (*declared)(void *context, const MsBinding *binding, const MsBindingList *scope);
  /* Every expression, before its parts; may be NULL. */
  void (*expr)(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site);
  /* A name read: `expr` is a MS_E_NAME. `scope` lists the enclosing bindings, innermost last. */
  void (*name)(void *context, const MsExpr *expr, const MsBindingList *scope, const MsScopeSite *site);
  /* Whether the name read `expr` was reported unknown; may be NULL. A call whose callee is such a name gives its
   * arguments no context, so the walk skips them. */
  bool (*unknown)(void *context, const MsExpr *expr);
  /* An assignment whose target is a plain name (`stmt->u.assign.name`). */
  void (*assign)(void *context, const MsStmt *stmt, const MsBindingList *scope, const MsScopeSite *site);
  /* An assignment to a field or an element (`stmt->u.assign.target`), after its target was walked; may be NULL. */
  void (*store)(void *context, const MsStmt *stmt, const MsBindingList *scope, const MsScopeSite *site);
} MsScopeVisitor;

/* The binding of `name` in `scope`, or NULL. */
const MsBinding *ms_scope_lookup(const MsBindingList *scope, MsName name);

void ms_scope_walk_module(const MsModule *tree, const MsScopeVisitor *visitor, MsNames *names);

#endif
