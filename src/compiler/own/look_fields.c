/* compiler/own/look_fields.c: see look_fields.h. */
#include "compiler/own/look_fields.h"

#include "compiler/check/properties.h"

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

bool ms_own_look_record(const MsCheckProgram *program, MsTy ty) {
  return ms_check_look_record(program, ty);
}

bool ms_own_look_carrier(const MsCheckProgram *program, const MsCall *call, uint32_t index) {
  if (call->callee.kind != MS_REF_TYPE) {
    return false;
  }
  const MsTyRow *row = ms_ty_row(&program->types, ms_ty_result(&program->types, call->callee_ty));
  if (row->kind != MS_TY_TYPE || row->def == 0) {
    return false;
  }
  const MsDef *def = ms_defs_get(&program->defs, row->def);
  return index < def->fields.len && ms_check_look_record(program, def->fields.ptr[index].ty);
}

bool ms_own_look_member(const MsCheckProgram *program, const MsFacts *facts, const MsExpr *member) {
  const MsTy record = ms_facts_type(facts, member->u.member.left->id);
  const MsTyRow *row = record == MS_TY_NONE ? NULL : ms_ty_row(&program->types, record);
  if (row == NULL || row->kind != MS_TY_TYPE || row->def == 0) {
    return false;
  }
  const MsDef *def = ms_defs_get(&program->defs, row->def);
  const MsDecl *decl = program->symbols.ptr[def->symbol].decl;
  for (uint32_t index = 0; decl != NULL && decl->kind == MS_D_TYPE && index < decl->u.type.fields.len && index < def->fields.len; index++) {
    if (def->fields.ptr[index].name == member->u.member.name) {
      return decl->u.type.fields.ptr[index]->ty != NULL && decl->u.type.fields.ptr[index]->ty->is_ref;
    }
  }
  return false;
}
