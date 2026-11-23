/* compiler/own/bind.h: bindings as the ownership pass reads them from the checker's facts.
 *
 * A binding is a local or a parameter; its id is the node id of its binding site, which is unique per module.
 * A name use, a binding site and an assignment to a name all carry a MS_REF_LOCAL or MS_REF_PARAM reference
 * whose `decl` is the binding site. */
#ifndef MS_COMPILER_OWN_BIND_H
#define MS_COMPILER_OWN_BIND_H

#include "base/arena.h"
#include "compiler/check/facts.h"
#include "compiler/own/live_set.h"
#include "compiler/syntax/ast.h"

MS_LIST_DEFINE(MsBindingList, ms_binding_list, uint32_t)

/* Whether the list holds `binding`. */
static inline bool ms_binding_list_contains(const MsBindingList *list, uint32_t binding) {
  for (size_t index = 0; index < list->len; index++) {
    if (list->ptr[index] == binding) {
      return true;
    }
  }
  return false;
}

/* The binding `node` names; false when it resolves to anything but a local or a parameter. */
bool ms_bind_of(const MsFacts *facts, MsNode node, uint32_t *binding);

/* A chain of member reads on a local name (`b.f.g`): the root name, its binding and the field path. False for
 * a bare name or any other expression. */
bool ms_bind_field_chain(const MsFacts *facts, MsArena *arena, const MsExpr *expr, const MsExpr **root,
                         uint32_t *binding, MsLivePath *path);

/* The bindings a lambda uses that are bound outside it, in order of first use. Owned by the caller. */
/* Whether the call builds a value: its callee is a type or an enum case, maybe with type arguments applied. */
bool ms_bind_is_constructor(const MsFacts *facts, const MsExpr *call);

MsBindingList ms_bind_captures(const MsFacts *facts, const MsExpr *lambda);

#endif
