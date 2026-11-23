/* compiler/mir/mir_verify_types.h: what the operand-rule files of the MIR verifier share. */
#ifndef MS_COMPILER_MIR_MIR_VERIFY_TYPES_H
#define MS_COMPILER_MIR_MIR_VERIFY_TYPES_H

#include "base/message.h"
#include "compiler/mir/mir_print.h"
#include "compiler/mir/mir_verify.h"

typedef struct MvtCx {
  const MirVerifyCx *v;
  const MirModule *m;
  const MirFunc *f;
  const MirInst *in;
  uint32_t n;    /* operand count */
  bool has_res;
  MirTy res;
} MvtCx;

typedef const char *(*MvtRule)(const MvtCx *c);

#define MVT_TRY(expr) \
  do { \
    const char *mvt_err = (expr); \
    if (mvt_err != NULL) { \
      return mvt_err; \
    } \
  } while (0)

/* `format` (ms_message_format conversions) as a NUL-terminated C string in `arena`. */
const char *mvt_fmt_(MsArena *arena, const char *format, ...);
#define mvt_fmt(arena, ...) mvt_fmt_((arena), MS_FMT_ARGS(__VA_ARGS__))

/* Whether operand 0 and the result are a borrowing variant and its ordinary alternative. */
bool mvt_plain_of(const MvtCx *c);

/* The rules of each file, by opcode; an opcode a file does not own has none. */
extern const MvtRule mvt_rules_core[MOP_COUNT];
extern const MvtRule mvt_rules_data[MOP_COUNT];
extern const MvtRule mvt_rules_ops[MOP_COUNT];

/* ---- helpers ---- */

static inline MirTy mvt_t(const MvtCx *c, uint32_t i) { return c->f->values.ptr[c->in->args[i]]; }

static inline const MirTyData *mvt_data(const MvtCx *c, MirTy t) { return mir_ty_data(c->m, t); }

static inline MirTyKind mvt_kind(const MvtCx *c, MirTy t) { return (MirTyKind)mvt_data(c, t)->kind; }

static inline bool mvt_res_is(const MvtCx *c, MirTy t) { return c->has_res && c->res == t; }

static inline bool mvt_needs_drop(const MvtCx *c, MirTy t) { return c->v->drops[t]; }

static inline const char *mvt_want(bool cond, const char *msg) { return cond ? NULL : msg; }

static inline const char *mvt_arity(const MvtCx *c, uint32_t k) {
  if (c->n == k) {
    return NULL;
  }
  return mvt_fmt(c->v->arena, "expected %u operands, found %u", k, c->n);
}

static inline const char *mvt_type_name(const MvtCx *c, MirTy t) {
  MsStrBuild b = ms_strbuild_new();
  mir_print_ty(c->m, t, &b);
  const char *s = mvt_fmt(c->v->arena, "%S", ms_strbuild_span(&b));
  ms_strbuild_free(&b);
  return s;
}

static inline const char *mvt_name(const MvtCx *c, MsName s) {
  return mvt_fmt(c->v->arena, "%S", ms_names_span(&c->m->names, s));
}

static inline const char *mvt_mismatch(const MvtCx *c, const char *what, MirTy got, MirTy want) {
  return mvt_fmt(c->v->arena, "%s has type %s but %s is expected", what,
            mvt_type_name(c, got), mvt_type_name(c, want));
}

static inline const char *mvt_label(const MvtCx *c, const char *noun, uint32_t i) {
  return mvt_fmt(c->v->arena, "%s %u", noun, i);
}

static inline bool mvt_is_float(const MvtCx *c, MirTy t) {
  MirTyKind k = mvt_kind(c, t);
  return k == MK_FLOAT || k == MK_FLOAT32;
}

/* Bit width of an integer type, 0 for any other. */
static inline uint32_t mvt_int_bits(const MvtCx *c, MirTy t) {
  switch (mvt_kind(c, t)) {
  case MK_INT: case MK_UINT64: return 64;
  case MK_INT32: case MK_UINT32: return 32;
  case MK_INT16: case MK_UINT16: return 16;
  case MK_INT8: case MK_UINT8: return 8;
  case MK_VOID: case MK_BOOL: case MK_FLOAT: case MK_FLOAT32: case MK_STR: case MK_BYTES:
  case MK_PTR: case MK_TYPE: case MK_ALT: case MK_LIST: case MK_OPT: case MK_OBJ: case MK_FN:
  case MK_IFACE:
    return 0;
  }
  return 0;
}

static inline bool mvt_is_int(const MvtCx *c, MirTy t) { return mvt_int_bits(c, t) != 0; }

static inline bool mvt_is_kind_id(const MvtCx *c, MirTy t, MirTyKind kind, uint32_t id) {
  const MirTyData *d = mvt_data(c, t);
  return d->kind == kind && d->id == id;
}

static inline bool mvt_is_iface(const MvtCx *c, MirTy t) { return mvt_kind(c, t) == MK_IFACE; }

static inline bool mvt_list_elem(const MvtCx *c, MirTy t, MirTy *elem) {
  const MirTyData *d = mvt_data(c, t);
  if (d->kind != MK_LIST) {
    return false;
  }
  *elem = d->elem;
  return true;
}

/* The element of a list, or uint8 for bytes. */
static inline bool mvt_seq_elem(const MvtCx *c, MirTy t, MirTy *elem) {
  if (mvt_kind(c, t) == MK_BYTES) {
    *elem = MIR_UINT8;
    return true;
  }
  return mvt_list_elem(c, t, elem);
}

static inline bool mvt_opt_inner(const MvtCx *c, MirTy t, MirTy *inner) {
  const MirTyData *d = mvt_data(c, t);
  if (d->kind != MK_OPT) {
    return false;
  }
  *inner = d->elem;
  return true;
}

/* Whether the result is an optional of `want`. */
static inline bool mvt_res_opt_of(const MvtCx *c, MirTy want) {
  MirTy inner = 0;
  return c->has_res && mvt_opt_inner(c, c->res, &inner) && inner == want;
}

static inline bool mvt_borrows(const MirAltDef *a, uint32_t k) { return k < 64 && (a->borrowed >> k & 1); }

static inline bool mvt_alt_has_borrowed_cases(const MvtCx *c, MirTy t) {
  const MirTyData *d = mvt_data(c, t);
  return d->kind == MK_ALT && c->m->alts.ptr[d->id].borrowed != 0;
}

#endif
