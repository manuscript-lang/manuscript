/* Rules for lists, optionals, strings, closures and interfaces. (see mir_verify_types.h) */
#include "compiler/mir/mir_layout.h"
#include "compiler/mir/mir_verify_types.h"

/* ---- lists ---- */

static const char *mvt_list_new(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MirTy elem = 0;
  return mvt_want(mvt_t(c, 0) == MIR_INT && c->has_res && mvt_list_elem(c, c->res, &elem),
          "list.new takes a capacity and yields a list");
}

static const char *mvt_list_lit(const MvtCx *c) {
  MirTy elem = 0;
  if (!c->has_res || !mvt_list_elem(c, c->res, &elem)) {
    return "list.lit yields a list";
  }
  for (uint32_t i = 0; i < c->n; i++) {
    if (mvt_t(c, i) != elem) {
      return mvt_mismatch(c, "element", mvt_t(c, i), elem);
    }
  }
  return NULL;
}

static bool mvt_is_scalar_elem(const MvtCx *c, MirTy t) {
  MirTyKind k = mvt_kind(c, t);
  return k == MK_BOOL || k == MK_FLOAT || k == MK_FLOAT32 || mvt_is_int(c, t);
}

static const char *mvt_list_const(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  MirTy elem = 0;
  if (!c->has_res || !mvt_list_elem(c, c->res, &elem)) {
    return "list.const yields a list";
  }
  const MirImm *im = &c->in->imm;
  bool ok = im->tag == MI_INT && mvt_is_scalar_elem(c, elem) &&
       (uint64_t)im->i < c->m->list_consts.len;
  return mvt_want(ok, "list.const names constant data of a scalar element type");
}

static const char *mvt_list_len(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MirTy elem = 0;
  bool seq = mvt_list_elem(c, mvt_t(c, 0), &elem) || mvt_t(c, 0) == MIR_BYTES;
  return mvt_want(seq && mvt_res_is(c, MIR_INT), "list.len takes a list (or bytes) and yields int");
}

static const char *mvt_list_get(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  MirTy elem = 0;
  if (!mvt_seq_elem(c, mvt_t(c, 0), &elem)) {
    return "operand 0 must be a list";
  }
  return mvt_want(mvt_t(c, 1) == MIR_INT && mvt_res_is(c, elem),
          "index must be int; result is the element type");
}

static const char *mvt_list_release(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  MirTy elem = 0;
  if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
    return "operand 0 must be a list";
  }
  return mvt_want(mvt_t(c, 1) == MIR_INT && !c->has_res,
          "the first kept index must be int; no result");
}

static const char *mvt_list_store(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 3));
  MirTy elem = 0;
  if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
    return "operand 0 must be a list";
  }
  return mvt_want(mvt_t(c, 1) == MIR_INT && mvt_t(c, 2) == elem && mvt_res_is(c, mvt_t(c, 0)),
          "index must be int; value must be the element type; yields the updated list");
}

static const char *mvt_list_cap(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MirTy elem = 0;
  if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
    return "operand 0 must be a list";
  }
  return mvt_want(mvt_res_is(c, MIR_INT), "list.cap yields int");
}

static const char *mvt_list_grow(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  MirTy elem = 0;
  if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
    return "operand 0 must be a list";
  }
  return mvt_want(mvt_t(c, 1) == MIR_INT && mvt_res_is(c, mvt_t(c, 0)),
          "the new capacity must be int; yields the list with room for it");
}

static const char *mvt_list_push(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  MirTy elem = 0;
  if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
    return "operand 0 must be a list";
  }
  return mvt_want(mvt_t(c, 1) == elem && mvt_res_is(c, mvt_t(c, 0)),
          "value must be the element type; yields the updated list");
}

static const char *mvt_list_drop_last(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MirTy elem = 0;
  if (!mvt_list_elem(c, mvt_t(c, 0), &elem)) {
    return "operand 0 must be a list";
  }
  return mvt_want(mvt_res_is(c, mvt_t(c, 0)), "yields the shortened list");
}

/* ---- optionals ---- */

static const char *mvt_opt_wrap(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MVT_TRY(mvt_want(mvt_res_opt_of(c, mvt_t(c, 0)), "optional constructors wrap their operand"));
  /* A boxed optional holds its payload in a heap block, which a borrow cannot own. */
  return mvt_want(c->in->op == MOP_OptSome || !mir_layouts_opt_boxed(c->v->layouts, mvt_t(c, 0)),
          "opt.view cannot borrow a boxed optional");
}

static const char *mvt_opt_view_at(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MVT_TRY(mvt_want(mvt_t(c, 0) == MIR_PTR, "opt.view_at takes an address"));
  MirTy inner = 0;
  bool boxed = c->has_res && mvt_opt_inner(c, c->res, &inner) && mir_layouts_opt_boxed(c->v->layouts, inner);
  return mvt_want(boxed, "opt.view_at yields a boxed optional");
}

static const char *mvt_opt_none(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 0));
  MirTy inner = 0;
  return mvt_want(c->has_res && mvt_opt_inner(c, c->res, &inner), "opt.none yields an optional");
}

static const char *mvt_opt_is_some(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MirTy inner = 0;
  return mvt_want(mvt_opt_inner(c, mvt_t(c, 0), &inner) && mvt_res_is(c, MIR_BOOL),
          "opt.is_some takes an optional and yields bool");
}

static const char *mvt_opt_payload(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MirTy inner = 0;
  return mvt_want(mvt_opt_inner(c, mvt_t(c, 0), &inner) && mvt_res_is(c, inner),
          "yields the payload type");
}

static const char *mvt_opt_addr(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  MirTy inner = 0;
  return mvt_want(mvt_opt_inner(c, mvt_t(c, 0), &inner) && mvt_res_is(c, MIR_PTR),
          "opt.addr takes a present optional and yields a ptr to its payload");
}

/* ---- strings ---- */

/* A rule for `str -> int` ops: only the message differs. */
static const char *mvt_str_to_int(const MvtCx *c, const char *msg) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_STR && mvt_res_is(c, MIR_INT), msg);
}

static const char *mvt_str_len(const MvtCx *c) {
  return mvt_str_to_int(c, "str.len takes a string and yields int");
}

static const char *mvt_str_ascii_len(const MvtCx *c) {
  return mvt_str_to_int(c, "str.ascii_len takes a string and yields int");
}

static const char *mvt_str_bytes(const MvtCx *c) {
  return mvt_str_to_int(c, "str.bytes takes a string and yields its byte length");
}

static const char *mvt_str_byte(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_t(c, 0) == MIR_STR && mvt_t(c, 1) == MIR_INT && mvt_res_is(c, MIR_INT),
          "str.byte takes a string and a byte offset and yields int");
}

/* The literal of str.eq_lit is 1 to 8 bytes with no NUL. */
static bool mvt_eq_lit_ok(const MvtCx *c, const MirImm *im) {
  if (im->tag != MI_STR || im->a >= ms_names_count(&c->m->strings)) {
    return false;
  }
  MsSpan s = ms_names_span(&c->m->strings, im->a);
  for (size_t at = 0; at < s.len; at++) {
    if (s.ptr[at] == 0) {
      return false;
    }
  }
  return s.len >= 1 && s.len <= 8;
}

static const char *mvt_str_eq_lit(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_STR && mvt_res_is(c, MIR_BOOL) && mvt_eq_lit_ok(c, &c->in->imm),
          "str.eq_lit takes a string and a literal of 1 to 8 bytes without NUL and yields bool");
}

static const char *mvt_str_ascii(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_t(c, 0) == MIR_INT && mvt_res_is(c, MIR_STR),
          "str.ascii takes an ASCII byte and yields the shared one-character string");
}

static const char *mvt_bytes_push(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 2));
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_is_int(c, mvt_t(c, 1)) && mvt_res_is(c, MIR_BOOL),
          "bytes.push takes a builder address and a byte value and yields bool");
}

/* ---- closures and interfaces ---- */

/* The parameters after the environment, as a function type lists them. */
static bool mvt_closure_type_matches(const MvtCx *c, const MirFunc *callee) {
  const MirTyData *fn = mvt_data(c, c->res);
  uint32_t visible = callee->nparams > 0 ? callee->nparams - 1 : 0;
  if (fn->nargs != visible || fn->elem != callee->ret) {
    return false;
  }
  for (uint32_t i = 0; i < visible; i++) {
    if (fn->args[i] != callee->params[i + 1].ty) {
      return false;
    }
  }
  return true;
}

static const char *mvt_closure_params(const MvtCx *c, const MirFunc *callee) {
  const MirTyData *fn = mvt_data(c, c->res);
  for (uint32_t i = 1; i < callee->nparams; i++) {
    if ((callee->params[i].mode == MM_MOVE) != mir_owns(fn->owned, i - 1)) {
      return mvt_fmt(c->v->arena,
                "%s parameter %u must be `move` exactly where its function type passes it owned",
                mvt_name(c, callee->name), i - 1);
    }
  }
  return NULL;
}

static const char *mvt_closure_new(const MvtCx *c) {
  const MirImm *im = &c->in->imm;
  if (im->tag != MI_FUNC) {
    return "missing function";
  }
  if (im->a >= c->m->funcs.len) {
    return "bad function";
  }
  const MirFunc *callee = &c->m->funcs.ptr[im->a];
  if (callee->kind != MFK_CLOSURE) {
    return mvt_fmt(c->v->arena, "%s is not a closure function", mvt_name(c, callee->name));
  }
  if (c->n != callee->ncaptures) {
    return mvt_fmt(c->v->arena, "%s captures %u values, found %u", mvt_name(c, callee->name),
              callee->ncaptures, c->n);
  }
  for (uint32_t i = 0; i < c->n; i++) {
    if (mvt_t(c, i) != callee->captures[i]) {
      return mvt_mismatch(c, "capture", mvt_t(c, i), callee->captures[i]);
    }
  }
  if (!c->has_res || mvt_kind(c, c->res) != MK_FN) {
    return "closure.new yields a function type";
  }
  if (!mvt_closure_type_matches(c, callee)) {
    return "closure.new yields a function type matching the closure code";
  }
  return mvt_closure_params(c, callee);
}

/* The captures of the enclosing closure function and the index into them, or the error. */
static const char *mvt_capture_index(const MvtCx *c, const char *op, uint32_t *index) {
  if (c->in->imm.tag != MI_IDX) {
    return "missing index";
  }
  if (c->f->kind != MFK_CLOSURE) {
    return mvt_fmt(c->v->arena, "%s outside a closure function", op);
  }
  *index = c->in->imm.a;
  return NULL;
}

static const char *mvt_closure_cap(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  uint32_t i = 0;
  MVT_TRY(mvt_capture_index(c, "closure.cap", &i));
  if (i >= c->f->ncaptures) {
    return "capture index out of range";
  }
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, c->f->captures[i]),
          "closure.cap reads the environment (ptr) and yields the capture type");
}

static const char *mvt_closure_cap_addr(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  uint32_t i = 0;
  MVT_TRY(mvt_capture_index(c, "closure.cap_addr", &i));
  return mvt_want(mvt_t(c, 0) == MIR_PTR && mvt_res_is(c, MIR_PTR) && i < c->f->ncaptures,
          "closure.cap_addr takes the environment (ptr) and yields the capture's address");
}

static const char *mvt_iface_wrap(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  if (c->in->imm.tag != MI_VTABLE) {
    return "missing vtable";
  }
  if (c->in->imm.a >= c->m->vtables.len) {
    return "bad vtable";
  }
  const MirVtable *vt = &c->m->vtables.ptr[c->in->imm.a];
  return mvt_want(mvt_t(c, 0) == vt->data_ty && c->has_res &&
            mvt_is_kind_id(c, c->res, MK_IFACE, vt->iface),
          "iface.new and iface.borrow wrap the vtable's data type");
}

static const char *mvt_iface_view(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_is_iface(c, mvt_t(c, 0)) && mvt_res_is(c, mvt_t(c, 0)),
          "iface.view takes an interface value and yields the same type");
}

static const char *mvt_iface_is(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  if (c->in->imm.tag != MI_VTABLE) {
    return "missing vtable";
  }
  if (c->in->imm.a >= c->m->vtables.len) {
    return "bad vtable";
  }
  const MirVtable *vt = &c->m->vtables.ptr[c->in->imm.a];
  return mvt_want(mvt_is_kind_id(c, mvt_t(c, 0), MK_IFACE, vt->iface) && mvt_res_is(c, MIR_BOOL),
          "iface.is tests an interface value of the vtable's interface and yields bool");
}

static const char *mvt_iface_data(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_is_iface(c, mvt_t(c, 0)) && mvt_res_is(c, MIR_PTR),
          "iface.data takes an interface and yields ptr");
}

static const char *mvt_iface_tag(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_is_iface(c, mvt_t(c, 0)) && mvt_res_is(c, MIR_INT),
          "iface.tag takes an interface and yields int: 0 owns the box and payload, 1 only the box, 2 nothing");
}

static const char *mvt_iface_destroy(const MvtCx *c) {
  MVT_TRY(mvt_arity(c, 1));
  return mvt_want(mvt_is_iface(c, mvt_t(c, 0)) && !c->has_res,
          "iface.destroy takes an interface and runs its payload destructor");
}

const MvtRule mvt_rules_data[MOP_COUNT] = {
  [MOP_ListNew] = mvt_list_new, [MOP_ListLit] = mvt_list_lit, [MOP_ListConst] = mvt_list_const,
  [MOP_ListConstView] = mvt_list_const, [MOP_ListLen] = mvt_list_len, [MOP_ListGet] = mvt_list_get,
  [MOP_ListGetNn] = mvt_list_get, [MOP_ListGetU] = mvt_list_get, [MOP_ListTake] = mvt_list_get,
  [MOP_ListRelease] = mvt_list_release, [MOP_ListSet] = mvt_list_store, [MOP_ListSetNn] = mvt_list_store,
  [MOP_ListSetU] = mvt_list_store, [MOP_ListFill] = mvt_list_store, [MOP_ListFillU] = mvt_list_store,
  [MOP_ListPush] = mvt_list_push, [MOP_ListPushU] = mvt_list_push, [MOP_ListCap] = mvt_list_cap,
  [MOP_ListGrow] = mvt_list_grow, [MOP_ListDropLast] = mvt_list_drop_last, [MOP_OptSome] = mvt_opt_wrap,
  [MOP_OptView] = mvt_opt_wrap, [MOP_OptViewAt] = mvt_opt_view_at, [MOP_OptNone] = mvt_opt_none,
  [MOP_OptNoneOwned] = mvt_opt_none, [MOP_OptIsSome] = mvt_opt_is_some, [MOP_OptGet] = mvt_opt_payload,
  [MOP_OptUnwrap] = mvt_opt_payload, [MOP_OptUnbox] = mvt_opt_payload, [MOP_OptAddr] = mvt_opt_addr,
  [MOP_StrLen] = mvt_str_len, [MOP_StrByte] = mvt_str_byte, [MOP_StrAscii] = mvt_str_ascii,
  [MOP_StrAsciiLen] = mvt_str_ascii_len, [MOP_StrEqLit] = mvt_str_eq_lit, [MOP_StrBytes] = mvt_str_bytes,
  [MOP_BytesPush] = mvt_bytes_push, [MOP_ClosureNew] = mvt_closure_new, [MOP_ClosureCap] = mvt_closure_cap,
  [MOP_ClosureCapAddr] = mvt_closure_cap_addr, [MOP_IfaceNew] = mvt_iface_wrap,
  [MOP_IfaceBorrow] = mvt_iface_wrap, [MOP_IfaceView] = mvt_iface_view, [MOP_IfaceIs] = mvt_iface_is,
  [MOP_IfaceTag] = mvt_iface_tag, [MOP_IfaceDestroy] = mvt_iface_destroy, [MOP_IfaceData] = mvt_iface_data,
};
