/* compiler/own/look_fields.c: see look_fields.h. */
#include "compiler/own/look_fields.h"

bool ms_own_look_field(const MsCheckProgram *program, const MsCall *call, uint32_t index) {
  if (call->callee.kind != MS_REF_TYPE || call->callee.decl.module >= program->modules.len) {
    return false;
  }
  const MsModule *tree = program->modules.ptr[call->callee.decl.module].tree;
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    if (decl->kind == MS_D_TYPE && decl->id == call->callee.decl.node) {
      return index < decl->u.type.fields.len && decl->u.type.fields.ptr[index]->ty != NULL &&
             decl->u.type.fields.ptr[index]->ty->is_ref;
    }
  }
  return false;
}
