/* compiler/mir/mir_json_tree.c: the constructor thunk the runtime's tree parser builds `JsonValue` through. The
 * runtime never learns the alternative's layout (wiki: a runtime builder makes compiler-laid-out values through a
 * thunk): it hands each finished payload to this function, which moves it into the case's value. */
#include "compiler/mir/mir_json_tree.h"

#include "compiler/mir/mir_glue_internal.h"

enum { TREE_CASES = 6 };

bool mir_json_tree_shape(const MirModule *module, MirTy ty) {
  const MirTyData *data = mir_ty_data(module, ty);
  if (data->kind != MK_ALT || module->alts.ptr[data->id].std != MSTD_JSON_VALUE) {
    return false;
  }
  const MirAltDef *alt = &module->alts.ptr[data->id];
  if (alt->ncases != TREE_CASES) {
    return false;
  }
  for (uint32_t index = 0; index < TREE_CASES; index++) {
    if (alt->cases[index].nfields != (index == 0 ? 0u : 1u)) {
      return false;
    }
  }
  return true;
}

uint32_t mir_json_tree_ctor(MirModule *module, MirTy ty) {
  if (!mir_json_tree_shape(module, ty)) {
    return MIR_NONE;
  }
  const uint32_t alt = mir_ty_data(module, ty)->id;
  const MirCaseDef *cases = module->alts.ptr[alt].cases;
  const MirParam params[3] = {{MIR_INT, MM_BORROW}, {MIR_PTR, MM_BORROW}, {MIR_PTR, MM_BORROW}};
  MirBuilder b;
  mir_b_init(&b, module, mirgl_name(module, module->funcs.len, "json_tree_ctor"), params, 3, MIR_INT);
  MirValue args[3];
  mir_b_params(&b, args, 3);
  MirBlock blocks[TREE_CASES];
  MirCase switch_cases[TREE_CASES];
  for (uint32_t index = 0; index < TREE_CASES; index++) {
    blocks[index] = mir_b_new_block(&b);
    switch_cases[index] = (MirCase){.value = index, .target = {.block = blocks[index]}};
  }
  mir_b_switch(&b, args[0], switch_cases, TREE_CASES, blocks[0]);
  for (uint32_t index = 0; index < TREE_CASES; index++) {
    mir_b_seal_block(&b, blocks[index]);
    mir_b_switch_to(&b, blocks[index]);
    MirValue payload = MIR_NONE;
    if (index > 0) {
      payload = mirgl_take(&b, args[1], cases[index].fields[0].ty);
    }
    const MirValue value = mirgl_alt_new(&b, alt, index, &payload, index > 0 ? 1u : 0u);
    mirgl_put(&b, args[2], value);
    mir_b_ret(&b, mir_b_iconst(&b, 0));
  }
  return mirgl_finish(&b);
}
