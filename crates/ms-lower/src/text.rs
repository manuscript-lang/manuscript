//! Text forms: interpolation and `to_string`.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use ms_check::types::Kind;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, ExternDef, FuncId, Mode, Module, Param, Value};
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
    })
}

/// Calls a leaf formatter for scalar/string types; `None` for compound types.
fn scalar_text(b: &mut FuncBuilder<'_>, t: MTy, v: Value) -> Option<(Value, bool)> {
    let sym = if t == MTy::INT {
        "msrt_int_to_string"
    } else if t == MTy::FLOAT {
        "msrt_float_to_string"
    } else if t == MTy::BOOL {
        "msrt_bool_to_string"
    } else if t == MTy::STR {
        return Some((v, false));
    } else if t == MTy::UNIT {
        let s = b.str_lit("unit");
        return Some((s, false));
    } else {
        return None;
    };
    let ext = runtime_fn(b.m, sym, &[t], MTy::STR);
    Some((b.call_rt(ext, &[v]), true))
}

impl Cx {
    /// The function formatting a value of `t` (reserved on first use).
    pub(crate) fn format_fn(&mut self, m: &mut Module, t: MTy) -> FuncId {
        let key = format!("fmt:{}", t.0);
        if let Some(f) = self.helpers.get(&key) {
            return *f;
        }
        let f = ms_mir::ir::Func::new(
            "format",
            vec![Param {
                ty: t,
                mode: Mode::Borrow,
            }],
            MTy::STR,
        );
        let id = m.add_func(f);
        self.helpers.insert(key, id);
        self.queue.push(Job {
            func: id,
            kind: JobKind::Format(t),
        });
        id
    }
}

/// Appends `piece` to the owned accumulator variable.
fn append(b: &mut FuncBuilder<'_>, acc: ms_mir::builder::Var, piece: Value, piece_owned: bool) {
    let old = b.use_var(acc);
    let ext = runtime_fn(b.m, "msrt_string_concat", &[MTy::STR, MTy::STR], MTy::STR);
    let new = b.call_rt(ext, &[old, piece]);
    b.def_var(acc, new);
    b.emit(ms_mir::ir::Op::Drop, &[old], ms_mir::ir::Imm::None, None);
    if piece_owned {
        b.emit(ms_mir::ir::Op::Drop, &[piece], ms_mir::ir::Imm::None, None);
    }
}

/// Formats one element: scalars directly, compound types through their helper.
fn element_text(cx: &mut Cx, b: &mut FuncBuilder<'_>, t: MTy, v: Value) -> (Value, bool) {
    if let Some(r) = scalar_text(b, t, v) {
        return r;
    }
    let f = cx.format_fn(b.m, t);
    (b.call(f, &[v]), true)
}

/// Builds the body of a formatting helper.
pub(crate) fn build_format(cx: &mut Cx, m: &mut Module, func: FuncId, t: MTy) -> Result<(), Error> {
    let mut b = FuncBuilder::new(
        m,
        "format",
        vec![Param {
            ty: t,
            mode: Mode::Borrow,
        }],
        MTy::STR,
    );
    let x = b.params()[0];
    match b.m.types.kind(t).clone() {
        TyKind::List(elem) => {
            let open = b.str_lit("[");
            let first = b
                .emit(
                    ms_mir::ir::Op::Copy,
                    &[open],
                    ms_mir::ir::Imm::None,
                    Some(MTy::STR),
                )
                .expect("copy");
            let acc = b.declare_var(MTy::STR, Mode::Own);
            b.def_var(acc, first);
            let idx = b.declare_var(MTy::INT, Mode::Borrow);
            let zero = b.iconst(0);
            b.def_var(idx, zero);
            let n = b.list_len(x);
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
            let comma = b.str_lit(", ");
            append(&mut b, acc, comma, false);
            b.br(nosep, &[]);
            b.switch_to(nosep);
            let i = b.use_var(idx);
            let e = b.list_get(x, i);
            let (txt, owned) = element_text(cx, &mut b, elem, e);
            append(&mut b, acc, txt, owned);
            let i = b.use_var(idx);
            let one = b.iconst(1);
            let i1 = b.binop(ms_mir::ir::Op::IAdd, i, one);
            b.def_var(idx, i1);
            b.br(header, &[]);
            b.seal_block(header);
            b.seal_block(exit);
            b.switch_to(exit);
            let close = b.str_lit("]");
            append(&mut b, acc, close, false);
            let r = b.use_var(acc);
            b.ret(Some(r));
        }
        TyKind::Opt(inner) => {
            let (some, none) = (b.new_block(), b.new_block());
            let is = b.opt_is_some(x);
            b.br_if(is, some, &[], none, &[]);
            b.seal_block(some);
            b.seal_block(none);
            b.switch_to(none);
            let s = b.str_lit("Optional.none");
            let o = b
                .emit(
                    ms_mir::ir::Op::Copy,
                    &[s],
                    ms_mir::ir::Imm::None,
                    Some(MTy::STR),
                )
                .expect("copy");
            b.ret(Some(o));
            b.switch_to(some);
            let v = b.opt_get(x);
            let (txt, owned) = element_text(cx, &mut b, inner, v);
            let open = b.str_lit("Optional.some(");
            let first = b
                .emit(
                    ms_mir::ir::Op::Copy,
                    &[open],
                    ms_mir::ir::Imm::None,
                    Some(MTy::STR),
                )
                .expect("copy");
            let acc = b.declare_var(MTy::STR, Mode::Own);
            b.def_var(acc, first);
            append(&mut b, acc, txt, owned);
            let close = b.str_lit(")");
            append(&mut b, acc, close, false);
            let r = b.use_var(acc);
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
    /// The text form of an operand.
    pub fn format_value(&mut self, x: Val) -> Result<Val, Error> {
        let t = self.ty_of(x.v);
        if t == MTy::STR {
            return Ok(x);
        }
        let v = match scalar_text(&mut self.b, t, x.v) {
            Some((v, owned)) => return Ok(Val { v, own: owned }),
            None => {
                let f = self.cx.format_fn(self.b.m, t);
                let a = self.borrow(x);
                self.b.call(f, &[a])
            }
        };
        Ok(Val { v, own: true })
    }

    /// A text literal with interpolations.
    pub fn text(&mut self, parts: &[TextPart]) -> Result<Val, Error> {
        let mut acc: Option<Val> = None;
        for p in parts {
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
                    self.format_value(x)?
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
