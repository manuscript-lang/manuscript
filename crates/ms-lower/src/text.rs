//! Text forms: interpolation, `to_string` and the quoted form test failures print.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use ms_check::types::Kind;
use ms_mir::builder::{FuncBuilder, Var};
use ms_mir::ir::{Cc, ExternDef, FuncId, Imm, Mode, Module, Op, Param, Value, VtableId};
use ms_mir::print::ty_str;
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;

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
    })
}

/// The runtime formatter of a native record type whose text is not its fields.
fn native_record_text(b: &FuncBuilder<'_>, t: MTy) -> Option<&'static str> {
    let TyKind::Rec(rid) = b.m.types.kind(t) else {
        return None;
    };
    match b.m.records[rid.index()].name.as_str() {
        "Decimal" => Some("msstd_decimal_to_string"),
        "Timestamp" => Some("msstd_time_timestamp_to_string"),
        _ => None,
    }
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
    } else if t == MTy::UNIT {
        let s = b.str_lit("unit");
        return Some((s, false));
    } else {
        native_record_text(b, t)?
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
    /// The function formatting a value of `t` (reserved on first use); `repr` is the quoted form.
    pub(crate) fn format_fn(&mut self, m: &mut Module, t: MTy, repr: bool) -> FuncId {
        let key = format!("fmt:{}:{repr}", t.0);
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
    let ext = runtime_fn(b.m, "msrt_strbuf_push", &[MTy::PTR, MTy::STR], MTy::UNIT);
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
    let out = b.declare_var(MTy::STR, Mode::Own);
    let (cut, fmt, join) = (b.new_block(), b.new_block(), b.new_block());
    b.br_if(too_deep, cut, &[], fmt, &[]);
    b.seal_block(cut);
    b.seal_block(fmt);
    b.switch_to(cut);
    let dots = b.str_lit("...");
    let dots = b
        .emit(Op::Copy, &[dots], Imm::None, Some(MTy::STR))
        .expect("copy");
    b.def_var(out, dots);
    b.br(join, &[]);
    b.switch_to(fmt);
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
        b.emit(Op::Copy, &[txt], Imm::None, Some(MTy::STR))
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
    let x = b.params()[0];
    let depth = b.params()[1];
    match b.m.types.kind(t).clone() {
        TyKind::Rec(_) | TyKind::Alt(_) if cx.opaque_tys.contains(&t) => {
            // An opaque value shows its type name only, never its hidden fields.
            let name = match b.m.types.kind(t).clone() {
                TyKind::Rec(r) => b.m.records[r.index()].name.clone(),
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
            let acc = start(&mut b, if repr { "none" } else { "Optional.none" });
            let r = finish(&mut b, acc);
            b.ret(Some(r));
            b.switch_to(some);
            let v = b.opt_get(x);
            let acc = start(&mut b, if repr { "some" } else { "Optional.some" });
            append_fields(cx, &mut b, acc, &[(None, inner, v)], repr, depth);
            let r = finish(&mut b, acc);
            b.ret(Some(r));
        }
        TyKind::Rec(r) => {
            let def = b.m.records[r.index()].clone();
            let mut order: Vec<usize> = (0..def.fields.len()).collect();
            if !repr {
                order.sort_by(|a, c| def.fields[*a].0.cmp(&def.fields[*c].0));
            }
            let mut vals = Vec::new();
            for i in order {
                let v = b.rec_get(r, i as u32, x);
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
                let head = if repr {
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
        TyKind::Obj(n, args) if n == "Map" || n == "Set" => {
            let is_map = n == "Map";
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
        TyKind::Obj(name, _) if name == "BigInt" => {
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
                .emit(Op::Copy, &[lit], Imm::None, Some(MTy::STR))
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
        if let TyKind::Rec(rid) = self.b.m.types.kind(t).clone()
            && self.b.m.records[rid.index()].name == "Timestamp"
        {
            // RFC 3339 text from the runtime, which takes the two words by address.
            let slot = self
                .b
                .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
                .expect("slot");
            let a = self.borrow(x);
            self.b.emit(Op::Store, &[slot, a], Imm::None, None);
            let v = self.call_runtime("msstd_time_timestamp_to_string", &[slot], MTy::STR)?;
            return Ok(Val { v, own: true });
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

    /// The text of a `Duration`: `Duration.to_string` from `@std/time.ms`.
    pub(crate) fn duration_text(&mut self, x: Val) -> Result<Val, Error> {
        let method = self
            .cx
            .methods
            .iter()
            .find(|m| {
                m.receiver.is_std("Duration")
                    && m.decl.as_ref().is_some_and(|d| d.name() == "to_string")
            })
            .ok_or_else(|| Error::new("Duration.to_string not found"))?;
        let callable =
            self.callable_of_decl(method.module, method.decl.as_ref().map(|d| d.id()))?;
        let f = self
            .cx
            .function_for(self.b.m, &callable, &ms_check::types::Subst::new())?;
        let n = self.borrow(x);
        let v = self.b.call(f, &[n]);
        Ok(Val { v, own: true })
    }

    /// A text literal with interpolations.
    pub fn text(&mut self, parts: &[TextPart]) -> Result<Val, Error> {
        let mut acc: Option<Val> = None;
        for (n, p) in parts.iter().enumerate() {
            let piece = match p {
                TextPart::Lit(s) => {
                    let v = self.b.str_lit(s);
                    Val { v, own: false }
                }
                TextPart::Interp(e) => {
                    let x = self.expr(e)?;
                    if self.dead {
                        return Ok(x);
                    }
                    let _ = Kind::Record;
                    if self.ety(e).is_std("Duration") {
                        self.duration_text(x)?
                    } else {
                        self.format_value(x)?
                    }
                }
            };
            acc = Some(match acc {
                None => piece,
                Some(a) => {
                    let av = self.borrow(a);
                    let pv = self.borrow(piece);
                    let r = self.call_runtime("msrt_string_concat", &[av, pv], MTy::STR)?;
                    Val { v: r, own: true }
                }
            });
            // A later part may return early (`try`): the text built so far is a temporary.
            let later_try = parts[n + 1..]
                .iter()
                .any(|l| matches!(l, TextPart::Interp(e) if crate::mutation::has_try(e)));
            if later_try && let Some(a) = acc {
                acc = Some(self.hold_temp(a));
            }
        }
        match acc {
            Some(a) => Ok(a),
            None => {
                let v = self.b.str_lit("");
                Ok(Val { v, own: false })
            }
        }
    }
}
