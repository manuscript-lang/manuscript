//! Text forms: interpolation, `to_string` and the quoted form test failures print.

use crate::Error;
use crate::cx::HelperKey;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use ms_check::api::ast::*;
use ms_check::api::types::Kind;
use ms_mir::builder::{FuncBuilder, Var};
use ms_mir::ir::{
    Cc, ExternDef, ExternRole, FuncId, Imm, Mode, Module, Op, Param, Value, VtableId,
};
use ms_mir::print::ty_str;
use ms_mir::types::Native;
use ms_mir::types::{Ty as MTy, TyKind};

/// One part of an interpolation, ready to join.
pub(crate) enum Piece {
    Str(Val),
    Int(Value),
}

/// Most pieces one joined call takes (`msrt_string_concatN` and `msrt_string_fmtN` stop at six).
const MAX_JOIN: usize = 6;

/// A readable name of a MIR type for diagnostics.
pub(crate) fn ty_name(m: &Module, t: MTy) -> String {
    ty_str(m, t)
}

/// Declares a runtime function with all operands borrowed.
pub(crate) fn runtime_fn(m: &mut Module, sym: &str, params: &[MTy], ret: MTy) -> ms_mir::ir::ExtId {
    m.add_extern(ExternDef {
        name: sym.to_string(),
        params: params
            .iter()
            .map(|t| Param {
                ty: *t,
                mode: Mode::Borrow,
            })
            .collect(),
        ret,
        noreturn: false,
        pure_: false,
        fresh: crate::rtcall::fresh_result(sym),
        role: crate::rtcall::extern_role(sym),
        leaf: crate::rtcall::rt_flags(sym).leaf,
        reads: crate::rtcall::rt_flags(sym).reads,
    })
}

/// Calls a leaf formatter for scalar/string types; `None` for compound types.
/// The quoted form (`repr`) wraps strings in quotes.
pub(crate) fn scalar_text(
    b: &mut FuncBuilder<'_>,
    t: MTy,
    v: Value,
    repr: bool,
) -> Option<(Value, bool)> {
    let sym = if t == MTy::UINT64 {
        "msrt_uint_to_string"
    } else if b.m.types.is_int(t) {
        "msrt_int_to_string"
    } else if t == MTy::FLOAT32 {
        "msrt_float32_to_string"
    } else if t == MTy::FLOAT {
        "msrt_float_to_string"
    } else if t == MTy::BOOL {
        "msrt_bool_to_string"
    } else if t == MTy::STR {
        if repr {
            let ext = runtime_fn(b.m, "msrt_string_quote", &[MTy::STR], MTy::STR);
            return Some((b.call_rt(ext, &[v]), true));
        }
        return Some((v, false));
    } else if t == MTy::VOID {
        let s = b.str_lit("void");
        return Some((s, false));
    } else {
        return None;
    };
    let ext = runtime_fn(b.m, sym, &[t], MTy::STR);
    Some((b.call_rt(ext, &[v]), true))
}

/// Nesting depth at which conversion emits `...` (the outer value is depth 0).
const MAX_TEXT_DEPTH: i64 = 64;

/// A formatting helper takes the value and its nesting depth.
fn format_params(t: MTy) -> Vec<Param> {
    [t, MTy::INT]
        .into_iter()
        .map(|ty| Param {
            ty,
            mode: Mode::Borrow,
        })
        .collect()
}

impl Cx {
    /// The function of the `fn T.to_string() String` a record or enum declares for `concrete`
    /// (specialized for a generic type's arguments): its text form wherever a value of that type
    /// is shown, nested in a container too.
    pub(crate) fn own_text_fn(
        &mut self,
        m: &mut Module,
        concrete: &ms_check::api::types::Ty,
    ) -> Result<Option<FuncId>, Error> {
        use ms_check::api::types as ct;
        if !matches!(concrete.kind, Kind::Type | Kind::Alternative | Kind::Native) {
            return Ok(None);
        }
        // The interface names the operation and its signature; nothing here spells it.
        let Some(op) = self.session.sole_operation("@std/core.ms", "Stringable") else {
            return Ok(None);
        };
        let stringable = self.session.standard("Stringable", Vec::new());
        for at in self.method_index.candidates(concrete.id, op) {
            let c = &self.methods[at];
            let Some(decl) = &c.decl else { continue };
            if c.native != ct::Native::Source || !c.supplies(self.syms, &stringable) {
                continue;
            }
            let mut subst = ct::Subst::default();
            let vars = ct::variable_set(&c.variables);
            if !ct::unify(&c.receiver, concrete, &vars, &mut subst) {
                continue;
            }
            let callable = self
                .callables
                .get(&(c.module, decl.id()))
                .cloned()
                .ok_or_else(|| Error::new("to_string not found"))?;
            return Ok(Some(self.function_for(m, &callable, &subst)?));
        }
        Ok(None)
    }

    /// The function formatting a value of `t` (reserved on first use); `repr` is the quoted form.
    pub(crate) fn format_fn(&mut self, m: &mut Module, t: MTy, repr: bool) -> FuncId {
        let key = HelperKey::Fmt(t, repr);
        if let Some(f) = self.helpers.get(&key) {
            return *f;
        }
        let f = ms_mir::ir::Func::new("format", format_params(t), MTy::STR);
        let id = m.add_func(f);
        self.helpers.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Format(t, repr),
        });
        id
    }
}

/// Appends `piece` to the string builder held by `acc`.
fn append(b: &mut FuncBuilder<'_>, acc: Var, piece: Value, piece_owned: bool) {
    let buf = b.use_var(acc);
    let ext = runtime_fn(b.m, "msrt_strbuf_push", &[MTy::PTR, MTy::STR], MTy::VOID);
    b.call_rt(ext, &[buf, piece]);
    if piece_owned {
        b.emit(Op::Drop, &[piece], Imm::None, None);
    }
}

fn append_lit(b: &mut FuncBuilder<'_>, acc: Var, text: &str) {
    let l = b.str_lit(text);
    append(b, acc, l, false);
}

/// A string builder variable that already holds `text`.
fn start(b: &mut FuncBuilder<'_>, text: &str) -> Var {
    let ext = runtime_fn(b.m, "msrt_strbuf_new", &[], MTy::PTR);
    let buf = b.call_rt(ext, &[]);
    let acc = b.declare_var(MTy::PTR, Mode::Borrow);
    b.def_var(acc, buf);
    if !text.is_empty() {
        append_lit(b, acc, text);
    }
    acc
}

/// The builder's text as an owned string; the builder is consumed.
fn finish(b: &mut FuncBuilder<'_>, acc: Var) -> Value {
    let buf = b.use_var(acc);
    let ext = runtime_fn(b.m, "msrt_strbuf_finish", &[MTy::PTR], MTy::STR);
    b.call_rt(ext, &[buf])
}

/// Formats one element nested in a container at `depth`: scalars directly, compound types through
/// their helper, and `...` once the element would sit at the maximum depth.
fn element_text(
    cx: &mut Cx,
    b: &mut FuncBuilder<'_>,
    t: MTy,
    v: Value,
    repr: bool,
    depth: Value,
) -> (Value, bool) {
    let one = b.iconst(1);
    let child = b.binop(Op::IAdd, depth, one);
    let limit = b.iconst(MAX_TEXT_DEPTH);
    let too_deep = b.icmp(Cc::Ge, child, limit);
    let out = b.declare_var(MTy::STR, Mode::Move);
    let (cut, fmt, join) = (b.new_block(), b.new_block(), b.new_block());
    b.br_if(too_deep, cut, &[], fmt, &[]);
    b.seal_block(cut);
    b.seal_block(fmt);
    b.switch_to(cut);
    let dots = b.str_lit("...");
    let dots = b
        .emit(Op::Clone, &[dots], Imm::None, Some(MTy::STR))
        .expect("copy");
    b.def_var(out, dots);
    b.br(join, &[]);
    b.switch_to(fmt);
    if t == MTy::STR && !repr {
        // An empty string inside a container shows as `""`, so `[""]` is not read as `[]`.
        let n = b.str_bytes(v);
        let zero = b.iconst(0);
        let empty = b.icmp(Cc::Eq, n, zero);
        let (quoted, plain) = (b.new_block(), b.new_block());
        b.br_if(empty, quoted, &[], plain, &[]);
        b.seal_block(quoted);
        b.seal_block(plain);
        b.switch_to(quoted);
        let marks = b.str_lit("\"\"");
        let marks = b
            .emit(Op::Clone, &[marks], Imm::None, Some(MTy::STR))
            .expect("copy");
        b.def_var(out, marks);
        b.br(join, &[]);
        b.switch_to(plain);
    }
    let (txt, owned) = match scalar_text(b, t, v, repr) {
        Some(r) => r,
        None => {
            let f = cx.format_fn(b.m, t, repr);
            (b.call(f, &[v, child]), true)
        }
    };
    let txt = if owned {
        txt
    } else {
        b.emit(Op::Clone, &[txt], Imm::None, Some(MTy::STR))
            .expect("copy")
    };
    b.def_var(out, txt);
    b.br(join, &[]);
    b.seal_block(join);
    b.switch_to(join);
    (b.use_var(out), true)
}

/// Appends `label: value` pieces of a field list as `(a: 1, b: 2)`.
fn append_fields(
    cx: &mut Cx,
    b: &mut FuncBuilder<'_>,
    acc: Var,
    fields: &[(Option<String>, MTy, Value)],
    repr: bool,
    depth: Value,
) {
    append_lit(b, acc, "(");
    for (i, (label, ty, v)) in fields.iter().enumerate() {
        if i > 0 {
            append_lit(b, acc, ", ");
        }
        if let Some(l) = label {
            append_lit(b, acc, &format!("{l}: "));
        }
        let (txt, owned) = element_text(cx, b, *ty, *v, repr, depth);
        append(b, acc, txt, owned);
    }
    append_lit(b, acc, ")");
}

/// Appends the elements of `list` separated by commas.
fn append_items(
    cx: &mut Cx,
    b: &mut FuncBuilder<'_>,
    acc: Var,
    list: Value,
    elem: MTy,
    repr: bool,
    depth: Value,
) {
    let idx = b.declare_var(MTy::INT, Mode::Borrow);
    let zero = b.iconst(0);
    b.def_var(idx, zero);
    let n = b.list_len(list);
    let (header, body, exit) = (b.new_block(), b.new_block(), b.new_block());
    b.br(header, &[]);
    b.switch_to(header);
    let i = b.use_var(idx);
    let c = b.icmp(Cc::Lt, i, n);
    b.br_if(c, body, &[], exit, &[]);
    b.seal_block(body);
    b.switch_to(body);
    let i = b.use_var(idx);
    let first = b.icmp(Cc::Eq, i, zero);
    let (sep, nosep) = (b.new_block(), b.new_block());
    b.br_if(first, nosep, &[], sep, &[]);
    b.seal_block(sep);
    b.seal_block(nosep);
    b.switch_to(sep);
    append_lit(b, acc, ", ");
    b.br(nosep, &[]);
    b.switch_to(nosep);
    let i = b.use_var(idx);
    let e = b.list_get(list, i);
    let (txt, owned) = element_text(cx, b, elem, e, repr, depth);
    append(b, acc, txt, owned);
    let i = b.use_var(idx);
    let one = b.iconst(1);
    let i1 = b.binop(Op::IAdd, i, one);
    b.def_var(idx, i1);
    b.br(header, &[]);
    b.seal_block(header);
    b.seal_block(exit);
    b.switch_to(exit);
}

/// Builds the body of a formatting helper.
pub(crate) fn build_format(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    t: MTy,
    repr: bool,
) -> Result<(), Error> {
    let mut b = FuncBuilder::new(m, "format", format_params(t), MTy::STR);
    // Formatting recursive data recurses: it checks the stack like any recursive function.
    b.emit(Op::DepthEnter, &[], Imm::None, None);
    let x = b.params()[0];
    let depth = b.params()[1];
    let own_text = match cx.source_tys.get(t.0 as usize).cloned() {
        Some(concrete) => cx.own_text_fn(b.m, &concrete)?,
        None => None,
    };
    match b.m.types.kind(t).clone() {
        TyKind::Type(_) | TyKind::Alt(_) if own_text.is_some() => {
            // The type's own `to_string`, declared next to it.
            let f = own_text.expect("checked");
            let text = b.call(f, &[x]);
            b.ret(Some(text));
        }
        TyKind::Type(_) | TyKind::Alt(_) if cx.opaque_tys.contains(t.0 as usize) => {
            // An opaque value shows its type name only, never its hidden fields.
            let name = match b.m.types.kind(t).clone() {
                TyKind::Type(r) => b.m.type_defs[r.index()].name.clone(),
                TyKind::Alt(a) => b.m.alts[a.index()].name.clone(),
                _ => String::new(),
            };
            let acc = start(&mut b, &name);
            let out = finish(&mut b, acc);
            b.ret(Some(out));
        }
        TyKind::List(elem) => {
            let acc = start(&mut b, "[");
            append_items(cx, &mut b, acc, x, elem, repr, depth);
            append_lit(&mut b, acc, "]");
            let r = finish(&mut b, acc);
            b.ret(Some(r));
        }
        TyKind::Bytes => {
            let acc = start(&mut b, "Bytes(");
            let list_ty = b.m.types.list(MTy::UINT8);
            let ext = runtime_fn(b.m, "msrt_bytes_values", &[t], list_ty);
            let values = b.call_rt(ext, &[x]);
            append_items(cx, &mut b, acc, values, MTy::UINT8, repr, depth);
            b.emit(Op::Drop, &[values], Imm::None, None);
            append_lit(&mut b, acc, ")");
            let r = finish(&mut b, acc);
            b.ret(Some(r));
        }
        TyKind::Opt(inner) => {
            let (some, none) = (b.new_block(), b.new_block());
            let is = b.opt_is_some(x);
            b.br_if(is, some, &[], none, &[]);
            b.seal_block(some);
            b.seal_block(none);
            b.switch_to(none);
            let acc = start(&mut b, "none");
            let r = finish(&mut b, acc);
            b.ret(Some(r));
            b.switch_to(some);
            let v = b.opt_get(x);
            let acc = start(&mut b, "some");
            append_fields(cx, &mut b, acc, &[(None, inner, v)], repr, depth);
            let r = finish(&mut b, acc);
            b.ret(Some(r));
        }
        TyKind::Type(r) => {
            let def = b.m.type_defs[r.index()].clone();
            let mut order: Vec<usize> = (0..def.fields.len()).collect();
            if !repr {
                order.sort_by(|a, c| def.fields[*a].0.cmp(&def.fields[*c].0));
            }
            let mut vals = Vec::new();
            for i in order {
                let v = b.type_get(r, i as u32, x);
                vals.push((Some(def.fields[i].0.clone()), def.fields[i].1, v));
            }
            let acc = start(&mut b, def.name.split('[').next().unwrap_or(&def.name));
            append_fields(cx, &mut b, acc, &vals, repr, depth);
            let out = finish(&mut b, acc);
            b.ret(Some(out));
        }
        TyKind::Alt(a) => {
            let def = b.m.alts[a.index()].clone();
            let tag = b.alt_tag(x);
            let blocks: Vec<_> = def.cases.iter().map(|_| b.new_block()).collect();
            let arms: Vec<(i64, _)> = blocks
                .iter()
                .enumerate()
                .map(|(i, k)| (i as i64, *k))
                .collect();
            b.switch(tag, &arms, blocks[0]);
            for (i, c) in def.cases.iter().enumerate() {
                b.seal_block(blocks[i]);
                b.switch_to(blocks[i]);
                let base = def.name.split('[').next().unwrap_or(&def.name);
                // `Result` prints as its source cases (`ok(1)`), like `Optional`'s `some(3)`.
                let head = if repr || base == "Result" {
                    c.name.clone()
                } else {
                    // Generic arguments are not part of the printed name.
                    format!(
                        "{}.{}",
                        def.name.split('[').next().unwrap_or(&def.name),
                        c.name
                    )
                };
                let acc = start(&mut b, &head);
                if !c.fields.is_empty() {
                    let mut vals = Vec::new();
                    for (j, (name, ft)) in c.fields.iter().enumerate() {
                        let v = b.alt_get(a, i as u32, j as u32, x);
                        vals.push((repr.then(|| name.clone()), *ft, v));
                    }
                    append_fields(cx, &mut b, acc, &vals, repr, depth);
                }
                let out = finish(&mut b, acc);
                b.ret(Some(out));
            }
        }
        TyKind::Obj(n, args) if n.is_map_or_set() => {
            let is_map = n == Native::Map;
            let acc = start(&mut b, if is_map { "Map(" } else { "Set(" });
            let ptr_ty = MTy::PTR;
            let desc = |b: &mut FuncBuilder<'_>, t: MTy| {
                b.emit(Op::TypeDesc, &[], Imm::Ty(t), Some(ptr_ty))
                    .expect("typedesc")
            };
            let kd = desc(&mut b, args[0]);
            let vd = match args.get(1) {
                Some(v) => desc(&mut b, *v),
                None => b.iconst(0),
            };
            let count_ext = runtime_fn(b.m, "msrt_map_slot_count", &[t], MTy::INT);
            let count = b.call_rt(count_ext, &[x]);
            let idx = b.declare_var(MTy::INT, Mode::Borrow);
            let zero = b.iconst(0);
            b.def_var(idx, zero);
            let seen = b.declare_var(MTy::BOOL, Mode::Borrow);
            let no = b.bconst(false);
            b.def_var(seen, no);
            let (header, body, exit) = (b.new_block(), b.new_block(), b.new_block());
            b.br(header, &[]);
            b.switch_to(header);
            let i = b.use_var(idx);
            let more = b.icmp(Cc::Lt, i, count);
            b.br_if(more, body, &[], exit, &[]);
            b.seal_block(body);
            b.switch_to(body);
            let i = b.use_var(idx);
            let slot = |b: &mut FuncBuilder<'_>| {
                b.emit(Op::Slot, &[], Imm::Ty(ptr_ty), Some(ptr_ty))
                    .expect("slot")
            };
            let (kp, vp) = (slot(&mut b), slot(&mut b));
            let call_args = [x, kd, vd, i, kp, vp];
            let tys: Vec<MTy> = call_args.iter().map(|v| b.ty(*v)).collect();
            let entry_ext = runtime_fn(b.m, "msrt_map_entry_ptrs", &tys, MTy::BOOL);
            let live = b.call_rt(entry_ext, &call_args);
            let (item, next) = (b.new_block(), b.new_block());
            b.br_if(live, item, &[], next, &[]);
            b.seal_block(item);
            b.switch_to(item);
            let was = b.use_var(seen);
            let (sep, nosep) = (b.new_block(), b.new_block());
            b.br_if(was, sep, &[], nosep, &[]);
            b.seal_block(sep);
            b.seal_block(nosep);
            b.switch_to(sep);
            append_lit(&mut b, acc, ", ");
            b.br(nosep, &[]);
            b.switch_to(nosep);
            let yes = b.bconst(true);
            b.def_var(seen, yes);
            let kaddr = b
                .emit(Op::Load, &[kp], Imm::Ty(ptr_ty), Some(ptr_ty))
                .expect("load");
            let key = b
                .emit(Op::Load, &[kaddr], Imm::Ty(args[0]), Some(args[0]))
                .expect("load");
            let (txt, owned) = element_text(cx, &mut b, args[0], key, repr, depth);
            append(&mut b, acc, txt, owned);
            if let Some(vt) = args.get(1) {
                append_lit(&mut b, acc, ": ");
                let vaddr = b
                    .emit(Op::Load, &[vp], Imm::Ty(ptr_ty), Some(ptr_ty))
                    .expect("load");
                let val = b
                    .emit(Op::Load, &[vaddr], Imm::Ty(*vt), Some(*vt))
                    .expect("load");
                let (txt, owned) = element_text(cx, &mut b, *vt, val, repr, depth);
                append(&mut b, acc, txt, owned);
            }
            b.br(next, &[]);
            b.seal_block(next);
            b.switch_to(next);
            let i = b.use_var(idx);
            let one = b.iconst(1);
            let i1 = b.binop(Op::IAdd, i, one);
            b.def_var(idx, i1);
            b.br(header, &[]);
            b.seal_block(header);
            b.seal_block(exit);
            b.switch_to(exit);
            append_lit(&mut b, acc, ")");
            let r = finish(&mut b, acc);
            b.ret(Some(r));
        }
        TyKind::Obj(Native::BigInt, _) => {
            let ext = runtime_fn(
                b.m,
                "msstd_bigint_to_string_radix",
                &[t, MTy::INT],
                MTy::STR,
            );
            let ten = b.iconst(10);
            let r = b.call_rt(ext, &[x, ten]);
            b.ret(Some(r));
        }
        TyKind::Fn(..) | TyKind::Obj(..) => {
            // Functions and native objects print as a fixed marker.
            let text = if matches!(b.m.types.kind(t), TyKind::Fn(..)) {
                "[function]"
            } else {
                "[object]"
            };
            let lit = b.str_lit(text);
            let r = b
                .emit(Op::Clone, &[lit], Imm::None, Some(MTy::STR))
                .expect("copy");
            b.ret(Some(r));
        }
        TyKind::Iface(iface) => {
            // The text of the dynamic value: test each implementation table, in creation order.
            let tables: Vec<_> =
                b.m.vtables
                    .iter()
                    .enumerate()
                    .filter(|(_, v)| v.iface == iface)
                    .map(|(i, v)| (VtableId(i as u32), v.data_ty))
                    .collect();
            for (vt, data_ty) in tables {
                let hit = b
                    .emit(Op::IfaceIs, &[x], Imm::Vtable(vt), Some(MTy::BOOL))
                    .expect("test");
                let (yes, next) = (b.new_block(), b.new_block());
                b.br_if(hit, yes, &[], next, &[]);
                b.seal_block(yes);
                b.seal_block(next);
                b.switch_to(yes);
                let data = b
                    .emit(Op::IfaceData, &[x], Imm::None, Some(MTy::PTR))
                    .expect("data");
                let v = b
                    .emit(Op::Load, &[data], Imm::Ty(data_ty), Some(data_ty))
                    .expect("load");
                let acc = start(&mut b, "");
                let (txt, owned) = element_text(cx, &mut b, data_ty, v, repr, depth);
                append(&mut b, acc, txt, owned);
                let r = finish(&mut b, acc);
                b.ret(Some(r));
                b.switch_to(next);
            }
            let acc = start(&mut b, "");
            let r = finish(&mut b, acc);
            b.ret(Some(r));
        }
        _ => {
            return Err(Error::new(format!(
                "no text form for {} yet",
                ty_str(b.m, t)
            )));
        }
    }
    let mut f = b.into_func();
    f.compact_blocks();
    m.funcs[func.index()] = f;
    Ok(())
}

impl<'a> FnLower<'a> {
    /// The quoted text form of a borrowed operand (how test failures show values); owned.
    pub fn repr_text(&mut self, v: Value) -> Val {
        let t = self.ty_of(v);
        // The value itself is depth 0, one level below this notional container.
        let outside = self.b.iconst(-1);
        let (r, owned) = element_text(self.cx, &mut self.b, t, v, true, outside);
        Val { v: r, own: owned }
    }

    /// The text form of an operand.
    pub fn format_value(&mut self, x: Val) -> Result<Val, Error> {
        let t = self.ty_of(x.v);
        if t == MTy::STR {
            return Ok(x);
        }
        let v = match scalar_text(&mut self.b, t, x.v, false) {
            Some((v, owned)) => return Ok(Val { v, own: owned }),
            None => {
                let f = self.cx.format_fn(self.b.m, t, false);
                let a = self.borrow(x);
                let top = self.b.iconst(0);
                self.b.call(f, &[a, top])
            }
        };
        Ok(Val { v, own: true })
    }

    /// The text a type's own `fn T.to_string() String` gives `x`, which replaces the built-in
    /// text form; none when `t` declares no such method.
    pub(crate) fn own_to_string(
        &mut self,
        t: &ms_check::api::types::Ty,
        x: Val,
    ) -> Result<Option<Val>, Error> {
        if !matches!(t.kind, Kind::Type | Kind::Alternative) {
            return Ok(None);
        }
        let Some(f) = self.cx.own_text_fn(self.b.m, t)? else {
            return Ok(None);
        };
        let receiver = self.borrow(x);
        let text = self.b.call(f, &[receiver]);
        Ok(Some(Val { v: text, own: true }))
    }

    /// The text of a `Duration`: `Duration.to_string` from `@std/time.ms`.
    pub(crate) fn duration_text(&mut self, x: Val) -> Result<Val, Error> {
        let n = self.borrow(x);
        let v = self.time_call(ms_check::api::types::Builtin::Duration, "to_string", &[n])?;
        Ok(Val { v, own: true })
    }

    /// Calls the method `name` of a type of `@std/time.ms` (`Duration`, `Instant`,
    /// `Timestamp`) with the receiver first.
    pub(crate) fn time_call(
        &mut self,
        builtin: ms_check::api::types::Builtin,
        name: &str,
        args: &[Value],
    ) -> Result<Value, Error> {
        let method = self
            .cx
            .methods
            .iter()
            .find(|m| {
                m.receiver.is(builtin)
                    && m.decl
                        .as_ref()
                        .is_some_and(|d| self.syms.str(d.name()) == name)
            })
            .ok_or_else(|| Error::new(format!("{builtin:?}.{name} not found")))?;
        let callable =
            self.callable_of_decl(method.module, method.decl.as_ref().map(|d| d.id()))?;
        let f =
            self.cx
                .function_for(self.b.m, &callable, &ms_check::api::types::Subst::default())?;
        Ok(self.b.call(f, args))
    }

    /// The nanosecond count of a `Duration`.
    pub(crate) fn duration_nanos(&mut self, d: Value) -> Result<Value, Error> {
        let t = self.ty_of(d);
        let TyKind::Type(rid) = self.b.m.types.kind(t).clone() else {
            return Err(Error::new("Duration is not a type"));
        };
        Ok(self.b.type_get(rid, 0, d))
    }

    /// The `Duration` holding `nanos`.
    pub(crate) fn duration_of(&mut self, nanos: Value) -> Result<Value, Error> {
        let t = self
            .cx
            .lower_ty(self.b.m, &self.cx.session.time_type("Duration"))?;
        let TyKind::Type(rid) = self.b.m.types.kind(t).clone() else {
            return Err(Error::new("Duration is not a type"));
        };
        Ok(self.b.type_new(rid, &[nanos]))
    }

    /// `a + b + c` over strings: the operands are evaluated left to right and joined by one
    /// runtime call, like the pieces of an interpolation.
    pub(crate) fn text_sum(&mut self, e: &Expr) -> Result<Val, Error> {
        let pieces = self.sum_pieces(e)?;
        if self.dead {
            return Ok(self.dummy(MTy::STR));
        }
        self.at(e.pos);
        self.join_pieces(pieces)
    }

    /// The operands of `a + b + c` over strings, evaluated left to right; empty when evaluation
    /// left the function (`self.dead`).
    pub(crate) fn sum_pieces(&mut self, e: &Expr) -> Result<Vec<Piece>, Error> {
        let mut leaves: Vec<&Expr> = Vec::new();
        let mut cur = e;
        while let ExprKind::Binary {
            op: BinaryOp::Add,
            left,
            right,
        } = &cur.kind
        {
            leaves.push(right);
            cur = left;
        }
        leaves.push(cur);
        leaves.reverse();
        // `s = s + n.to_string()` stays a concatenation of `s`: the runtime grows `s` in place,
        // which a join of `s` and the integer would copy.
        let accumulates = leaves.len() == 2
            && matches!((&leaves[0].kind, self.assigning), (ExprKind::Name(n), Some(a)) if *n == a);
        let mut pieces = Vec::with_capacity(leaves.len());
        for leaf in leaves {
            let x = self.expr(leaf)?;
            if self.dead {
                return Ok(Vec::new());
            }
            // The text of a plain `Int` that was just rendered joins as the integer itself, so
            // `"n=" + n.to_string()` builds no temporary string.
            let int = if x.own && !accumulates {
                self.b.retract_call(x.v, ExternRole::IntToString, MTy::INT)
            } else {
                None
            };
            pieces.push(match int {
                Some(args) => Piece::Int(args[0]),
                None => Piece::Str(self.hold_temp(x)),
            });
        }
        Ok(pieces)
    }

    /// A text literal with interpolations: its pieces are evaluated left to right and joined by
    /// one runtime call, with a plain `Int` piece written in decimal by the join itself.
    pub fn text(&mut self, parts: &[TextPart]) -> Result<Val, Error> {
        let pieces = self.text_pieces(parts)?;
        if self.dead {
            return Ok(self.dummy(MTy::STR));
        }
        match pieces.as_slice() {
            [] => {
                let v = self.b.str_lit("");
                Ok(Val { v, own: false })
            }
            // A lone `"{s}"` is a new string, but reading it borrows `s` until an owning
            // position needs a value: that copy is the interpolation's, not a lowering gap.
            [Piece::Str(a)] => {
                let a = *a;
                if !a.own {
                    self.boundary_reads.insert(a.v);
                }
                Ok(a)
            }
            [Piece::Int(v)] => self.format_value(Val { v: *v, own: false }),
            _ => self.join_pieces(pieces),
        }
    }

    /// The pieces of a text literal, evaluated left to right; empty when evaluation left the
    /// function (`self.dead`).
    pub(crate) fn text_pieces(&mut self, parts: &[TextPart]) -> Result<Vec<Piece>, Error> {
        let mut pieces: Vec<Piece> = Vec::with_capacity(parts.len());
        for p in parts {
            let piece = match p {
                TextPart::Lit(s) => {
                    let v = self.b.str_lit(s);
                    Piece::Str(Val { v, own: false })
                }
                TextPart::Interp(e) => {
                    let x = self.expr(e)?;
                    if self.dead {
                        return Ok(Vec::new());
                    }
                    let t = self.ety(e);
                    if self.ty_of(x.v) == MTy::INT && !t.is(ms_check::api::types::Builtin::Duration)
                    {
                        Piece::Int(x.v)
                    } else if t.is(ms_check::api::types::Builtin::Duration) {
                        Piece::Str(self.duration_text(x)?)
                    } else if let Some(text) = self.own_to_string(&t, x)? {
                        Piece::Str(text)
                    } else {
                        Piece::Str(self.format_value(x)?)
                    }
                }
            };
            // A later piece may return early (`try`) or fault: what is built so far is a
            // temporary the statement drops, so every owned piece is registered when it exists.
            // A borrowed piece stays valid across later pieces because the checker rejects a
            // text whose operand changes or moves another operand.
            pieces.push(match piece {
                Piece::Str(v) => Piece::Str(self.hold_temp(v)),
                int => int,
            });
        }
        Ok(pieces)
    }

    /// Joins pieces with `msrt_string_concatN` or, when one is an integer, `msrt_string_fmtN`,
    /// at most `MAX_JOIN` per call; a longer text joins the first group, then that result and
    /// the next pieces.
    pub(crate) fn join_pieces(&mut self, pieces: Vec<Piece>) -> Result<Val, Error> {
        let mut rest = pieces.into_iter();
        let mut group: Vec<Piece> = rest.by_ref().take(MAX_JOIN).collect();
        loop {
            let joined = self.join_group(&group)?;
            let more: Vec<Piece> = rest.by_ref().take(MAX_JOIN - 1).collect();
            if more.is_empty() {
                return Ok(joined);
            }
            let held = self.hold_temp(joined);
            group = std::iter::once(Piece::Str(held)).chain(more).collect();
        }
    }

    fn join_group(&mut self, group: &[Piece]) -> Result<Val, Error> {
        let ints = group.iter().any(|p| matches!(p, Piece::Int(_)));
        let mut args = Vec::with_capacity(group.len() + 1);
        let mut mask = 0i64;
        for (k, p) in group.iter().enumerate() {
            match p {
                Piece::Int(v) => {
                    mask |= 1 << k;
                    args.push(*v);
                }
                Piece::Str(v) => args.push(self.borrow(*v)),
            }
        }
        let sym = match (ints, group.len()) {
            (false, 2) => "msrt_string_concat".to_string(),
            (false, n) => format!("msrt_string_concat{n}"),
            (true, n) => format!("msrt_string_fmt{n}"),
        };
        if ints {
            let m = self.b.iconst(mask);
            args.insert(0, m);
        }
        let r = self.call_runtime(&sym, &args, MTy::STR)?;
        Ok(Val { v: r, own: true })
    }
}
