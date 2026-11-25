/* The folding half of `simplify`: constant folding, algebraic identities, strength reduction and
 * the trivial block-parameter elimination. Constants go on the right of commutative operations. */
#include <math.h>

#include "compiler/opt/opt_simplify.h"

/* ---- the environment ---- */

enum { SFK_NONE, SFK_INT, SFK_FLOAT, SFK_BOOL };

/* A known constant: an integer, the bits of a float, or a boolean (0 or 1). */
typedef struct SfK {
  uint8_t kind;
  int64_t bits;
} SfK;

/* What a value was defined by: its opcode, operands and immediate. */
typedef struct SfDef {
  uint8_t op;
  uint32_t nargs;
  const MirValue *args; /* `inl` when the operands fit */
  MirValue inl[4];
  MirImm imm;
} SfDef;

/* Per value of the function. `known` and `defined` flag which entries of `consts` and `defs` are set, so the
 * large entries are never cleared: only a byte per value is. */
typedef struct SfEnv {
  MirModule *m;
  MirFunc *f;
  MsArena *arena;
  SfK *consts;
  SfDef *defs;
  uint8_t *known, *defined;
  uint32_t cap;
} SfEnv;

/* Makes room for every value of the function (it grows while the pass makes constants). */
static void sf_env_fit(SfEnv *e) {
  if (e->f->values.len <= e->cap && e->consts != NULL) {
    return;
  }
  const uint32_t cap = (uint32_t)(e->f->values.len + e->f->values.len / 2 + 8);
  SfK *consts = MS_ARENA_NEW_ARRAY_UNINIT(e->arena, SfK, cap);
  SfDef *defs = MS_ARENA_NEW_ARRAY_UNINIT(e->arena, SfDef, cap);
  uint8_t *known = MS_ARENA_NEW_ARRAY(e->arena, uint8_t, cap);
  uint8_t *defined = MS_ARENA_NEW_ARRAY(e->arena, uint8_t, cap);
  for (uint32_t v = 0; v < e->cap && e->consts != NULL; v++) {
    known[v] = e->known[v];
    defined[v] = e->defined[v];
    if (known[v]) {
      consts[v] = e->consts[v];
    }
    if (defined[v]) {
      defs[v] = e->defs[v];
      defs[v].args = e->defs[v].args == e->defs[v].inl ? defs[v].inl : e->defs[v].args;
    }
  }
  e->consts = consts;
  e->defs = defs;
  e->known = known;
  e->defined = defined;
  e->cap = cap;
}

static SfK sf_const(const SfEnv *e, MirValue v) {
  return v < e->cap && e->known[v] ? e->consts[v] : (SfK){SFK_NONE, 0};
}

static void sf_set_const(SfEnv *e, MirValue v, SfK k) {
  sf_env_fit(e);
  e->consts[v] = k;
  e->known[v] = 1;
}

static void sf_set_def(SfEnv *e, MirValue r, uint8_t op, const MirValue *args, uint32_t nargs,
           MirImm imm) {
  sf_env_fit(e);
  SfDef *d = &e->defs[r];
  e->defined[r] = 1;
  d->op = op;
  d->nargs = nargs;
  MirValue *own = nargs <= 4 ? d->inl : MS_ARENA_NEW_ARRAY(e->arena, MirValue, nargs);
  d->args = own;
  if (nargs > 0) {
    __builtin_memcpy(own, args, sizeof(MirValue) * nargs);
  }
  d->imm = imm;
}

static const SfDef *sf_def(const SfEnv *e, MirValue v) {
  return v < e->cap && e->defined[v] ? &e->defs[v] : NULL;
}

/* The integer (or boolean) constant `v` holds. */
static bool sf_ci(const SfEnv *e, MirValue v, int64_t *out) {
  const SfK k = sf_const(e, v);
  if (k.kind != SFK_INT && k.kind != SFK_BOOL) {
    return false;
  }
  *out = k.bits;
  return true;
}

static bool sf_ci_is(const SfEnv *e, MirValue v, int64_t want) {
  int64_t x = 0;
  return sf_ci(e, v, &x) && x == want;
}

static bool sf_cf(const SfEnv *e, MirValue v, double *out) {
  const SfK k = sf_const(e, v);
  if (k.kind != SFK_FLOAT) {
    return false;
  }
  const uint64_t bits = (uint64_t)k.bits;
  __builtin_memcpy(out, &bits, sizeof *out);
  return true;
}

static bool sf_is_pow2(int64_t x) { return x > 1 && (x & (x - 1)) == 0; }

static uint32_t sf_trailing_zeros(int64_t x) {
  uint32_t n = 0;
  for (uint64_t u = (uint64_t)x; (u & 1) == 0 && n < 64; u >>= 1) {
    n++;
  }
  return n;
}

static MirImm sf_imm_int(int64_t x) { return (MirImm){.tag = MI_INT, .i = x}; }

static MirValue sf_mk_const(SfEnv *e, OptInstVec *out, MirTy ty, int64_t v, MirLoc loc) {
  const MirValue r = mir_new_value(e->f, ty);
  const MirInst inst = opt_inst_make(e->m, MOP_IConst, NULL, 0, sf_imm_int(v), r, loc);
  opt_inst_vec_push(e->arena, out, &inst);
  sf_set_const(e, r, (SfK){SFK_INT, v});
  sf_set_def(e, r, MOP_IConst, NULL, 0, sf_imm_int(v));
  return r;
}

/* ---- evaluation ---- */

static bool sf_sized_range(const MirModule *m, MirTy t, int64_t *lo, int64_t *hi) {
  switch ((MirTyKind)mir_ty_data(m, t)->kind) {
  case MK_INT8: *lo = INT8_MIN; *hi = INT8_MAX; return true;
  case MK_INT16: *lo = INT16_MIN; *hi = INT16_MAX; return true;
  case MK_INT32: *lo = INT32_MIN; *hi = INT32_MAX; return true;
  case MK_UINT8: *lo = 0; *hi = UINT8_MAX; return true;
  case MK_UINT16: *lo = 0; *hi = UINT16_MAX; return true;
  case MK_UINT32: *lo = 0; *hi = UINT32_MAX; return true;
  default: return false;
  }
}

/* Whether the folded value `r` of `inst` is within the range of the sized type a checked
 * operation yields: out of it the operation faults, so it is not a constant. */
static bool sf_in_type(const SfEnv *e, const MirInst *inst, int64_t r) {
  const bool checked = inst->op == MOP_IAddChk || inst->op == MOP_ISubChk ||
            inst->op == MOP_IMulChk || inst->op == MOP_INegChk ||
            inst->op == MOP_SDivChk;
  int64_t lo = 0, hi = 0;
  if (!checked || inst->res == MIR_NONE ||
    !sf_sized_range(e->m, e->f->values.ptr[inst->res], &lo, &hi)) {
    return true;
  }
  return r >= lo && r <= hi;
}

static uint64_t sf_mulhi(uint64_t x, uint64_t y) {
  const uint64_t xl = x & 0xFFFFFFFFu, xh = x >> 32, yl = y & 0xFFFFFFFFu, yh = y >> 32;
  const uint64_t ll = xl * yl, lh = xl * yh, hl = xh * yl, hh = xh * yh;
  const uint64_t mid = (ll >> 32) + (lh & 0xFFFFFFFFu) + (hl & 0xFFFFFFFFu);
  return hh + (lh >> 32) + (hl >> 32) + (mid >> 32);
}

static uint64_t sf_rotl(uint64_t x, uint32_t n) {
  n &= 63;
  return n == 0 ? x : (x << n) | (x >> (64 - n));
}

/* Evaluates an integer operation when it cannot fault. */
static bool sf_int_op(MirOp op, int64_t x, int64_t y, int64_t *out) {
  const uint64_t ux = (uint64_t)x, uy = (uint64_t)y;
  const uint32_t sh = (uint32_t)y & 63;
  switch (op) {
  case MOP_IAdd: *out = (int64_t)(ux + uy); return true;
  case MOP_ISub: *out = (int64_t)(ux - uy); return true;
  case MOP_IMul: *out = (int64_t)(ux * uy); return true;
  case MOP_IAddChk: return !__builtin_add_overflow(x, y, out);
  case MOP_ISubChk: return !__builtin_sub_overflow(x, y, out);
  case MOP_IMulChk: return !__builtin_mul_overflow(x, y, out);
  case MOP_SDiv: case MOP_SDivChk:
    if (y == 0 || (x == INT64_MIN && y == -1)) {
      return false;
    }
    *out = x / y;
    return true;
  case MOP_SRemChk:
    if (y == 0) {
      return false;
    }
    *out = y == -1 ? 0 : x % y;
    return true;
  case MOP_SRem:
    if (y == 0 || (x == INT64_MIN && y == -1)) {
      return false;
    }
    *out = x % y;
    return true;
  case MOP_Shl: *out = (int64_t)(ux << sh); return true;
  case MOP_Sshr: *out = x < 0 ? (int64_t)~(~ux >> sh) : (int64_t)(ux >> sh); return true;
  case MOP_Ushr: *out = (int64_t)(ux >> sh); return true;
  case MOP_Rotl: *out = (int64_t)sf_rotl(ux, (uint32_t)(y & 63)); return true;
  case MOP_Rotr: *out = (int64_t)sf_rotl(ux, (64 - (uint32_t)(y & 63)) & 63); return true;
  case MOP_UMulHi: *out = (int64_t)sf_mulhi(ux, uy); return true;
  default: return false;
  }
}

static bool sf_eval_cc_float(uint32_t cc, double a, double b) {
  switch ((MirCc)cc) {
  case MCC_EQ: return a == b;
  case MCC_NE: return a != b;
  case MCC_LT: return a < b;
  case MCC_LE: return a <= b;
  case MCC_GT: return a > b;
  case MCC_GE: return a >= b;
  }
  return false;
}

/* ---- the rules ---- */

typedef enum SfActKind { SF_KEEP, SF_CONST, SF_ALIAS, SF_REWRITE } SfActKind;

typedef struct SfAct {
  uint8_t kind;
  SfK k;
  MirValue alias;
  uint8_t op;
  MirValue args[2];
  uint32_t nargs;
  MirImm imm;
} SfAct;

static SfAct sf_keep(void) { return (SfAct){.kind = SF_KEEP}; }
static SfAct sf_const_int(int64_t x) { return (SfAct){.kind = SF_CONST, .k = {SFK_INT, x}}; }
static SfAct sf_const_bool(bool x) { return (SfAct){.kind = SF_CONST, .k = {SFK_BOOL, x}}; }
static SfAct sf_const_float(double x) {
  int64_t bits = 0;
  __builtin_memcpy(&bits, &x, sizeof bits);
  return (SfAct){.kind = SF_CONST, .k = {SFK_FLOAT, bits}};
}
static SfAct sf_alias(MirValue v) { return (SfAct){.kind = SF_ALIAS, .alias = v}; }
static SfAct sf_rewrite1(MirOp op, MirValue a) {
  return (SfAct){.kind = SF_REWRITE, .op = (uint8_t)op, .args = {a, 0}, .nargs = 1};
}
static SfAct sf_rewrite2(MirOp op, MirValue a, MirValue b, MirImm imm) {
  return (SfAct){.kind = SF_REWRITE, .op = (uint8_t)op, .args = {a, b}, .nargs = 2, .imm = imm};
}

static SfAct sf_zero_of(bool is_bool) { return is_bool ? sf_const_bool(false) : sf_const_int(0); }

static SfAct sf_const_result(const SfEnv *e, const MirInst *inst, bool ok, int64_t r) {
  return ok && sf_in_type(e, inst, r) ? sf_const_int(r) : sf_keep();
}

/* `x + y`, `x - y`, `x * y` and their checked forms. */
static SfAct sf_arith_rule(SfEnv *e, OptInstVec *out, const MirInst *inst) {
  const MirValue x = inst->args[0], y = inst->args[1];
  int64_t p = 0, q = 0;
  if (sf_ci(e, x, &p) && sf_ci(e, y, &q)) {
    int64_t r = 0;
    const bool ok = sf_int_op((MirOp)inst->op, p, q, &r);
    return sf_const_result(e, inst, ok, r);
  }
  switch ((MirOp)inst->op) {
  case MOP_IAdd: case MOP_IAddChk:
    if (sf_ci_is(e, y, 0)) {
      return sf_alias(x);
    }
    return sf_ci_is(e, x, 0) ? sf_alias(y) : sf_keep();
  case MOP_ISub: case MOP_ISubChk:
    if (sf_ci_is(e, y, 0)) {
      return sf_alias(x);
    }
    return x == y ? sf_const_int(0) : sf_keep();
  default:
    break;
  }
  if (sf_ci_is(e, y, 1)) {
    return sf_alias(x);
  }
  if (sf_ci_is(e, x, 1)) {
    return sf_alias(y);
  }
  if (sf_ci_is(e, y, 0) || sf_ci_is(e, x, 0)) {
    return sf_const_int(0);
  }
  int64_t c = 0;
  if (inst->op == MOP_IMul && sf_ci(e, y, &c) && sf_is_pow2(c)) {
    const MirValue k = sf_mk_const(e, out, e->f->values.ptr[x], (int64_t)sf_trailing_zeros(c), inst->loc);
    return sf_rewrite2(MOP_Shl, x, k, (MirImm){0});
  }
  return sf_keep();
}

static SfAct sf_neg_rule(const SfEnv *e, const MirInst *inst) {
  const MirValue x = inst->args[0];
  int64_t p = 0;
  if (sf_ci(e, x, &p)) {
    int64_t r = 0;
    bool ok = true;
    if (inst->op == MOP_INeg) {
      r = (int64_t)(0 - (uint64_t)p);
    } else {
      ok = p != INT64_MIN;
      r = ok ? -p : 0;
    }
    return sf_const_result(e, inst, ok, r);
  }
  const SfDef *d = sf_def(e, x);
  if (inst->op == MOP_INeg && d != NULL && d->op == MOP_INeg) {
    return sf_alias(d->args[0]);
  }
  return sf_keep();
}

static SfAct sf_div_rule(const SfEnv *e, const MirInst *inst) {
  const MirValue x = inst->args[0], y = inst->args[1];
  const bool div = inst->op == MOP_SDiv || inst->op == MOP_SDivChk;
  const bool chk = inst->op == MOP_SDivChk || inst->op == MOP_SRemChk;
  int64_t p = 0, q = 0;
  if (sf_ci(e, x, &p) && sf_ci(e, y, &q)) {
    int64_t r = 0;
    const bool ok = sf_int_op((MirOp)inst->op, p, q, &r);
    return sf_const_result(e, inst, ok, r);
  }
  if (!sf_ci(e, y, &q)) {
    return sf_keep();
  }
  /* Checked remainder defines MIN % -1 as zero, like the backend's safe-divisor sequence;
   * unlike division it cannot overflow. */
  if (q == -1 && inst->op == MOP_SRemChk) {
    return sf_const_int(0);
  }
  if (q == 1) {
    return div ? sf_alias(x) : sf_const_int(0);
  }
  if (q != 0 && q != -1 && chk) {
    return sf_rewrite2(div ? MOP_SDiv : MOP_SRem, x, y, (MirImm){0});
  }
  return sf_keep();
}

static SfAct sf_bit_rule(const SfEnv *e, const MirInst *inst, bool is_bool) {
  const MirValue x = inst->args[0], y = inst->args[1];
  int64_t p = 0, q = 0;
  if (sf_ci(e, x, &p) && sf_ci(e, y, &q)) {
    int64_t r = p ^ q;
    if (inst->op == MOP_And) {
      r = p & q;
    } else if (inst->op == MOP_Or) {
      r = p | q;
    }
    return is_bool ? sf_const_bool((r & 1) == 1) : sf_const_int(r);
  }
  if (x == y) {
    return inst->op == MOP_Xor ? sf_zero_of(is_bool) : sf_alias(x);
  }
  const int64_t ones = is_bool ? 1 : -1;
  if (!sf_ci(e, y, &q)) {
    return sf_keep();
  }
  if (inst->op == MOP_And && q == 0) {
    return sf_zero_of(is_bool);
  }
  if (inst->op == MOP_And && q == ones) {
    return sf_alias(x);
  }
  if ((inst->op == MOP_Or || inst->op == MOP_Xor) && q == 0) {
    return sf_alias(x);
  }
  if (inst->op == MOP_Xor && q == 1 && is_bool) {
    return sf_rewrite1(MOP_Not, x);
  }
  if (inst->op == MOP_Or && q == ones) {
    return is_bool ? sf_const_bool(true) : sf_const_int(-1);
  }
  return sf_keep();
}

static SfAct sf_shift_rule(const SfEnv *e, const MirInst *inst) {
  const MirValue x = inst->args[0], y = inst->args[1];
  int64_t p = 0, q = 0;
  if (sf_ci(e, x, &p) && sf_ci(e, y, &q)) {
    int64_t r = 0;
    return sf_int_op((MirOp)inst->op, p, q, &r) ? sf_const_int(r) : sf_keep();
  }
  return sf_ci(e, y, &q) && (q & 63) == 0 ? sf_alias(x) : sf_keep();
}

/* Integer arithmetic, negation, division, bit and shift identities. */
static SfAct sf_integer_rule(SfEnv *e, OptInstVec *out, const MirInst *inst) {
  const bool is_bool = inst->res != MIR_NONE && e->f->values.ptr[inst->res] == MIR_BOOL;
  switch ((MirOp)inst->op) {
  case MOP_IAdd: case MOP_ISub: case MOP_IMul: case MOP_IAddChk: case MOP_ISubChk:
  case MOP_IMulChk:
    return sf_arith_rule(e, out, inst);
  case MOP_INeg: case MOP_INegChk:
    return sf_neg_rule(e, inst);
  case MOP_SDiv: case MOP_SRem: case MOP_SDivChk: case MOP_SRemChk:
    return sf_div_rule(e, inst);
  case MOP_And: case MOP_Or: case MOP_Xor:
    return sf_bit_rule(e, inst, is_bool);
  case MOP_Shl: case MOP_Sshr: case MOP_Ushr: case MOP_Rotl: case MOP_Rotr:
    return sf_shift_rule(e, inst);
  default:
    return sf_keep();
  }
}

/* `(x % 2^k) ==/!= 0` tests the low bits of x. */
static SfAct sf_rem_test(SfEnv *e, OptInstVec *out, const MirInst *inst, MirValue x, MirValue y) {
  const SfDef *d = sf_def(e, x);
  int64_t c = 0;
  if (d == NULL || (d->op != MOP_SRem && d->op != MOP_SRemChk) || d->nargs < 2 ||
    !sf_ci(e, d->args[1], &c) || !sf_is_pow2(c)) {
    return sf_keep();
  }
  const MirValue operand = d->args[0];
  const MirTy ty = e->f->values.ptr[operand];
  const MirValue mask = sf_mk_const(e, out, ty, c - 1, inst->loc);
  const MirValue r = mir_new_value(e->f, ty);
  const MirValue and_args[2] = {operand, mask};
  const MirInst and_inst = opt_inst_make(e->m, MOP_And, and_args, 2, (MirImm){0}, r, inst->loc);
  opt_inst_vec_push(e->arena, out, &and_inst);
  sf_set_def(e, r, MOP_And, and_args, 2, (MirImm){0});
  return sf_rewrite2(MOP_ICmp, r, y, inst->imm);
}

static SfAct sf_icmp_rule(SfEnv *e, OptInstVec *out, const MirInst *inst) {
  if (inst->imm.tag != MI_CC) {
    return sf_keep();
  }
  const uint32_t cc = inst->imm.a;
  const MirValue x = inst->args[0], y = inst->args[1];
  int64_t p = 0, q = 0;
  if (sf_ci(e, x, &p) && sf_ci(e, y, &q)) {
    return sf_const_bool(mir_cc_holds((MirCc)cc, p, q));
  }
  if (x == y) {
    return sf_const_bool(cc == MCC_EQ || cc == MCC_LE || cc == MCC_GE);
  }
  if ((cc == MCC_EQ || cc == MCC_NE) && sf_ci_is(e, y, 0)) {
    return sf_rem_test(e, out, inst, x, y);
  }
  return sf_keep();
}

/* Boolean negation, comparisons and `select`. */
static SfAct sf_comparison_rule(SfEnv *e, OptInstVec *out, const MirInst *inst) {
  const bool is_bool = inst->res != MIR_NONE && e->f->values.ptr[inst->res] == MIR_BOOL;
  int64_t p = 0;
  switch ((MirOp)inst->op) {
  case MOP_Not: {
    if (sf_ci(e, inst->args[0], &p)) {
      return sf_const_bool(p == 0);
    }
    const SfDef *d = sf_def(e, inst->args[0]);
    return d != NULL && d->op == MOP_Not ? sf_alias(d->args[0]) : sf_keep();
  }
  case MOP_ICmp:
    return sf_icmp_rule(e, out, inst);
  case MOP_FCmp: {
    double a = 0, b = 0;
    if (inst->imm.tag != MI_CC || !sf_cf(e, inst->args[0], &a) || !sf_cf(e, inst->args[1], &b)) {
      return sf_keep();
    }
    return sf_const_bool(sf_eval_cc_float(inst->imm.a, a, b));
  }
  case MOP_Select: {
    const MirValue c = inst->args[0], t = inst->args[1], el = inst->args[2];
    if (sf_ci(e, c, &p)) {
      return sf_alias(p != 0 ? t : el);
    }
    if (t == el) {
      return sf_alias(t);
    }
    if (is_bool && sf_ci_is(e, t, 1) && sf_ci_is(e, el, 0)) {
      return sf_alias(c);
    }
    if (is_bool && sf_ci_is(e, t, 0) && sf_ci_is(e, el, 1)) {
      return sf_rewrite1(MOP_Not, c);
    }
    return sf_keep();
  }
  default:
    return sf_keep();
  }
}

/* A Float32 result is the nearest binary32 value, as the machine instruction computes it. */
static SfAct sf_const_float_of(const SfEnv *e, const MirInst *inst, double r) {
  const bool narrow = inst->res != MIR_NONE && e->f->values.ptr[inst->res] == MIR_FLOAT32;
  return sf_const_float(narrow ? (double)(float)r : r);
}

static SfAct sf_float_rule(const SfEnv *e, const MirInst *inst) {
  double p = 0, q = 0;
  switch ((MirOp)inst->op) {
  case MOP_FAdd: case MOP_FSub: case MOP_FMul: case MOP_FDiv: {
    if (!sf_cf(e, inst->args[0], &p) || !sf_cf(e, inst->args[1], &q)) {
      return sf_keep();
    }
    double r = p / q;
    if (inst->op == MOP_FAdd) {
      r = p + q;
    } else if (inst->op == MOP_FSub) {
      r = p - q;
    } else if (inst->op == MOP_FMul) {
      r = p * q;
    }
    return sf_const_float_of(e, inst, r);
  }
  default: {
    if (!sf_cf(e, inst->args[0], &p)) {
      return sf_keep();
    }
    double r = fabs(p);
    if (inst->op == MOP_FNeg) {
      r = -p;
    } else if (inst->op == MOP_FSqrt) {
      r = sqrt(p);
    } else if (inst->op == MOP_FFloor) {
      r = floor(p);
    } else if (inst->op == MOP_FCeil) {
      r = ceil(p);
    } else if (inst->op == MOP_FTrunc) {
      r = trunc(p);
    }
    return sf_const_float_of(e, inst, r);
  }
  }
}

static bool sf_scalar_payload(MirTy t) {
  return t == MIR_INT || t == MIR_BOOL || t == MIR_FLOAT || t == MIR_VOID || t == MIR_PTR;
}

static SfAct sf_optional_rule(const SfEnv *e, const MirInst *inst) {
  const SfDef *d = sf_def(e, inst->args[0]);
  switch ((MirOp)inst->op) {
  case MOP_OptIsSome:
    if (d != NULL && (d->op == MOP_OptSome || d->op == MOP_OptView)) {
      return sf_const_bool(true);
    }
    if (d != NULL && (d->op == MOP_OptNone || d->op == MOP_OptNoneOwned)) {
      return sf_const_bool(false);
    }
    return sf_keep();
  default:
    break;
  }
  /* A borrowed optional borrows its payload, so `opt.get` of it is the payload itself.
   * `opt.unwrap` owns its result, so it keeps copying. */
  if (inst->op == MOP_OptGet && d != NULL && d->op == MOP_OptView) {
    return sf_alias(d->args[0]);
  }
  if (d == NULL || d->op != MOP_OptSome) {
    return sf_keep();
  }
  /* A scalar has no ownership to transfer or copy. For an owned payload, the constructor
   * consumed it, so aliasing it here would revive a move. */
  return sf_scalar_payload(e->f->values.ptr[d->args[0]]) ? sf_alias(d->args[0]) : sf_keep();
}

/* Float arithmetic, numeric conversions and optionals. */
static SfAct sf_float_and_optional_rule(const SfEnv *e, const MirInst *inst) {
  int64_t p = 0;
  switch ((MirOp)inst->op) {
  case MOP_I2F: {
    if (!sf_ci(e, inst->args[0], &p)) {
      return sf_keep();
    }
    const bool narrow = inst->res != MIR_NONE && e->f->values.ptr[inst->res] == MIR_FLOAT32;
    return sf_const_float(narrow ? (double)(float)p : (double)p);
  }
  case MOP_B2I:
    return sf_ci(e, inst->args[0], &p) ? sf_const_int(p) : sf_keep();
  case MOP_OptIsSome: case MOP_OptGet: case MOP_OptUnwrap:
    return sf_optional_rule(e, inst);
  default:
    return sf_float_rule(e, inst);
  }
}

static SfAct sf_rule(SfEnv *e, OptInstVec *out, const MirInst *inst) {
  switch ((MirOp)inst->op) {
  case MOP_IAdd: case MOP_ISub: case MOP_IMul: case MOP_IAddChk: case MOP_ISubChk:
  case MOP_IMulChk: case MOP_INeg: case MOP_INegChk: case MOP_SDiv: case MOP_SRem:
  case MOP_SDivChk: case MOP_SRemChk: case MOP_And: case MOP_Or: case MOP_Xor: case MOP_Shl:
  case MOP_Sshr: case MOP_Ushr: case MOP_Rotl: case MOP_Rotr: case MOP_UMulHi:
    return sf_integer_rule(e, out, inst);
  case MOP_Not: case MOP_ICmp: case MOP_FCmp: case MOP_Select:
    return sf_comparison_rule(e, out, inst);
  case MOP_FAdd: case MOP_FSub: case MOP_FMul: case MOP_FDiv: case MOP_FNeg: case MOP_FSqrt:
  case MOP_FAbs: case MOP_FFloor: case MOP_FCeil: case MOP_FTrunc: case MOP_I2F: case MOP_B2I:
  case MOP_OptIsSome: case MOP_OptGet: case MOP_OptUnwrap:
    return sf_float_and_optional_rule(e, inst);
  default:
    return sf_keep();
  }
}

/* A `fault.site` tests the fault of the check before it. Once an earlier pass has made that check an operation that
 * cannot fault (a proven range, a constant divisor), the test is false, and the exit it guards is dead. */
static SfAct sf_fault_site_rule(const SfEnv *e, const MirInst *inst) {
  const SfDef *def = sf_def(e, inst->args[0]);
  if (def != NULL && (mir_op_info[def->op].effects & MIR_E_FAULTS) == 0) {
    return sf_const_bool(false);
  }
  return sf_keep();
}

/* ---- folding ---- */

/* Records what instruction `i` defines: its constant value and its definition. */
static void sf_note_def(SfEnv *e, const MirInst *i) {
  const MirValue r = i->res;
  if (i->op == MOP_IConst && i->imm.tag == MI_INT) {
    sf_set_const(e, r, (SfK){SFK_INT, i->imm.i});
  } else if (i->op == MOP_FConst && i->imm.tag == MI_FLOAT) {
    sf_set_const(e, r, (SfK){SFK_FLOAT, i->imm.i});
  } else if (i->op == MOP_BConst && i->imm.tag == MI_BOOL) {
    sf_set_const(e, r, (SfK){SFK_BOOL, i->imm.a != 0});
  }
  sf_set_def(e, r, i->op, i->args, i->nargs, i->imm);
}

typedef struct SfFold {
  SfEnv *env;
  OptSubst *subst;
  bool changed;
} SfFold;

static void sf_resolve_use(void *ctx, MirValue *v) {
  *v = opt_subst_resolve(ctx, *v);
}

/* Constants go on the right of commutative operations. */
static bool sf_canonical_order(const SfEnv *e, MirInst *inst) {
  if (inst->nargs != 2 || sf_const(e, inst->args[0]).kind == SFK_NONE ||
    sf_const(e, inst->args[1]).kind != SFK_NONE) {
    return false;
  }
  const bool commutes = opt_op_commutative(inst->op, &inst->imm);
  if (!commutes && !(inst->op == MOP_ICmp && inst->imm.tag == MI_CC)) {
    return false;
  }
  const MirValue t = inst->args[0];
  inst->args[0] = inst->args[1];
  inst->args[1] = t;
  if (!commutes) {
    inst->imm.a = (uint32_t)mir_cc_swapped((MirCc)inst->imm.a);
  }
  return true;
}

/* Applies the rule's verdict to `inst`; false when the instruction is gone. */
static bool sf_apply(SfFold *fold, const SfAct *act, MirInst *inst) {
  SfEnv *e = fold->env;
  switch ((SfActKind)act->kind) {
  case SF_KEEP:
    return true;
  case SF_ALIAS:
    opt_subst_set(fold->subst, inst->res, opt_subst_resolve(fold->subst, act->alias));
    fold->changed = true;
    return false;
  case SF_CONST: {
    MirOp op = MOP_IConst;
    MirImm imm = {.tag = MI_INT, .i = act->k.bits};
    if (act->k.kind == SFK_FLOAT) {
      op = MOP_FConst;
      imm = (MirImm){.tag = MI_FLOAT, .i = act->k.bits};
    } else if (act->k.kind == SFK_BOOL) {
      op = MOP_BConst;
      imm = (MirImm){.tag = MI_BOOL, .a = act->k.bits != 0};
    }
    const bool unchanged = inst->op == op && opt_imm_eq(&inst->imm, &imm);
    inst->op = (uint8_t)op;
    inst->imm = imm;
    inst->nargs = 0;
    sf_set_const(e, inst->res, act->k);
    fold->changed |= !unchanged;
    return true;
  }
  case SF_REWRITE:
    inst->op = act->op;
    inst->args = opt_inst_make(e->m, (MirOp)act->op, act->args, act->nargs, act->imm,
                 MIR_NONE, inst->loc).args;
    inst->nargs = act->nargs;
    inst->imm = act->imm;
    fold->changed = true;
    return true;
  }
  return true;
}

/* Folds `inst`, which has its operands resolved; false when it is deleted. */
static bool sf_fold_inst(SfFold *fold, OptInstVec *out, MirInst *inst) {
  SfEnv *e = fold->env;
  fold->changed |= sf_canonical_order(e, inst);
  /* A fault guard whose condition is known false never fires. */
  if (inst->op == MOP_IntOverflowIf) {
    const SfK k = sf_const(e, inst->args[0]);
    if (k.kind == SFK_BOOL && k.bits == 0) {
      fold->changed = true;
      return false;
    }
  }
  const SfAct act = inst->op == MOP_FaultSite ? sf_fault_site_rule(e, inst) : sf_rule(e, out, inst);
  if (!sf_apply(fold, &act, inst)) {
    return false;
  }
  if (inst->res != MIR_NONE) {
    sf_set_def(e, inst->res, inst->op, inst->args, inst->nargs, inst->imm);
  }
  return true;
}

/* Replaces a conditional branch or switch on a known value with a jump. */
static bool sf_fold_term(SfFold *fold, MirBlockData *b) {
  MirModule *m = fold->env->m;
  MirTerm *t = &b->term;
  int64_t c = 0;
  if (t->kind == MT_CONDBR) {
    MirTarget chosen = t->a;
    if (sf_ci(fold->env, t->value, &c)) {
      chosen = c != 0 ? t->a : t->b;
    } else if (!opt_target_eq(&t->a, &t->b)) {
      return false;
    }
    opt_term_set_br(t, opt_target_clone(m, &chosen));
    return true;
  }
  if (t->kind != MT_SWITCH || !sf_ci(fold->env, t->value, &c)) {
    return false;
  }
  MirTarget chosen = t->b;
  for (uint32_t k = 0; k < t->ncases; k++) {
    if (t->cases[k].value == c) {
      chosen = t->cases[k].target;
      break;
    }
  }
  opt_term_set_br(t, opt_target_clone(m, &chosen));
  return true;
}

bool opt_simplify_fold(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  SfEnv env = {.m = m, .f = f, .arena = &arena};
  sf_env_fit(&env);
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      if (f->blocks.ptr[bi].insts.ptr[ii].res != MIR_NONE) {
        sf_note_def(&env, &f->blocks.ptr[bi].insts.ptr[ii]);
      }
    }
  }
  OptSubst subst = opt_subst_new(&arena, (uint32_t)f->values.len);
  SfFold fold = {&env, &subst, false};
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    OptInstVec out = {0};
    for (uint32_t ii = 0; ii < f->blocks.ptr[bi].insts.len; ii++) {
      MirInst inst = f->blocks.ptr[bi].insts.ptr[ii];
      for (uint32_t k = 0; k < inst.nargs; k++) {
        inst.args[k] = opt_subst_resolve(&subst, inst.args[k]);
      }
      if (sf_fold_inst(&fold, &out, &inst)) {
        opt_inst_vec_push(&arena, &out, &inst);
      }
    }
    opt_block_set_insts(&f->blocks.ptr[bi], out.v, out.n);
    mir_term_each_use(&f->blocks.ptr[bi].term, sf_resolve_use, &subst);
    fold.changed |= sf_fold_term(&fold, &f->blocks.ptr[bi]);
  }
  opt_subst_apply(f, &subst);
  ms_arena_free(&arena);
  return fold.changed;
}
