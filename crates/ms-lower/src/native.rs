//! Standard-library natives: runtime calls and inline sequences.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::text::runtime_fn;
use ms_check::hir::CallView;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Linkage, Mode, Param, Value, VtableDef};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;

/// String operations `fn(String) -> String` and their runtime symbols.
const STRING_TO_STRING: &[(&str, &str)] = &[
    ("string/reverse", "msrt_string_reverse"),
    ("string/lower", "msrt_string_lower"),
    ("string/upper", "msrt_string_upper"),
    ("string/trim", "msrt_string_trim"),
    ("string/trim_start", "msrt_string_trim_start"),
    ("string/trim_end", "msrt_string_trim_end"),
];

/// A string method that maps its borrowed operands straight to a runtime function.
const PLAIN_STRING: &[(&str, &str, MTy)] = &[
    ("string/length", "msrt_string_length", MTy::INT),
    (
        "string/scalar_length",
        "msrt_string_scalar_length",
        MTy::INT,
    ),
    ("string/byte_length", "msrt_string_byte_length", MTy::INT),
    ("string/is_empty", "msrt_string_is_empty", MTy::BOOL),
    ("string/contains", "msrt_string_contains", MTy::BOOL),
    ("string/starts_with", "msrt_string_starts_with", MTy::BOOL),
    ("string/ends_with", "msrt_string_ends_with", MTy::BOOL),
    ("string/concat", "msrt_string_concat", MTy::STR),
    ("string/compare", "msrt_string_compare", MTy::INT),
];

/// An evaluated argument of a native call.
pub(crate) struct NArg {
    pub name: ms_check::types::Name,
    pub val: Val,
    pub wrapped: bool,
}

impl<'a> FnLower<'a> {
    pub fn native_function(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        native: &str,
    ) -> Result<Val, Error> {
        let _ = view;
        match native {
            "io/stdout" => self.std_stream(e, false),
            "io/stderr" => self.std_stream(e, true),
            other => Err(Error::new(format!("unsupported native function {other}"))),
        }
    }

    /// `stdout()` / `stderr()`: an interface value over a MIR-built vtable.
    fn std_stream(&mut self, e: &Expr, stderr: bool) -> Result<Val, Error> {
        let it = self.emty(e)?;
        let TyKind::Iface(iface) = self.b.m.types.kind(it).clone() else {
            return Err(Error::new("stdout() is not an interface"));
        };
        let key = format!(
            "vtable:{}:{}",
            if stderr { "stderr" } else { "stdout" },
            iface.0
        );
        let vt = match self.cx.vtables.get(&key) {
            Some(v) => *v,
            None => {
                let sigs = self.b.m.ifaces[iface.index()].methods.clone();
                let mut methods = Vec::new();
                for s in &sigs {
                    let f = build_stream_method(self.b.m, &s.name, &s.params, s.ret, stderr);
                    methods.push(f);
                }
                self.b.m.vtables.push(VtableDef {
                    name: key.clone(),
                    iface,
                    methods,
                    data_ty: MTy::UNIT,
                });
                let id = ms_mir::ir::VtableId(self.b.m.vtables.len() as u32 - 1);
                self.cx.vtables.insert(key, id);
                id
            }
        };
        let u = self.b.unit();
        let v = self
            .b
            .emit(
                ms_mir::ir::Op::IfaceNew,
                &[u],
                ms_mir::ir::Imm::Vtable(vt),
                Some(it),
            )
            .expect("iface");
        Ok(Val { v, own: true })
    }

    pub fn native_method(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
        recv: Val,
    ) -> Result<Val, Error> {
        let _ = recv_expr;
        let native = m.native.as_str();
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(recv);
        }
        self.at(e.pos);
        if let Some((_, sym)) = STRING_TO_STRING.iter().find(|(n, _)| *n == native) {
            let r = self.borrow(recv);
            let out = self.call_runtime(sym, &[r], MTy::STR)?;
            return Ok(Val { v: out, own: true });
        }
        if let Some((_, sym, ret)) = PLAIN_STRING.iter().find(|(n, _, _)| *n == native) {
            let mut vals = vec![self.borrow(recv)];
            for a in args {
                vals.push(self.borrow(a.val));
            }
            let out = self.call_runtime(sym, &vals, *ret)?;
            return Ok(self.val(out, *ret == MTy::STR));
        }
        let name = native.rsplit('/').next().unwrap_or(native);
        let rty = self.ty_of(recv.v);
        match (self.b.m.types.kind(rty).clone(), name) {
            (TyKind::Str, "replace" | "replace_first") => {
                let sym = if name == "replace" {
                    "msrt_string_replace"
                } else {
                    "msrt_string_replace_first"
                };
                let mut vals = vec![self.borrow(recv)];
                let mut max = None;
                for a in args {
                    if a.name.as_str() == "max_replacements" {
                        max = Some(a);
                    } else {
                        vals.push(self.borrow(a.val));
                    }
                }
                let (has, n) = self.optional_int(max)?;
                vals.push(has);
                vals.push(n);
                let out = self.call_runtime(sym, &vals, MTy::STR)?;
                Ok(Val { v: out, own: true })
            }
            (TyKind::Str, "replace_n") => {
                let mut vals = vec![self.borrow(recv)];
                for a in args {
                    vals.push(self.borrow(a.val));
                }
                let out = self.call_runtime("msrt_string_replace_n", &vals, MTy::STR)?;
                Ok(Val { v: out, own: true })
            }
            (TyKind::List(_), "length") => {
                let r = self.borrow(recv);
                let v = self.b.list_len(r);
                Ok(Val { v, own: false })
            }
            (TyKind::List(_), "is_empty") => {
                let r = self.borrow(recv);
                let n = self.b.list_len(r);
                let z = self.b.iconst(0);
                let v = self.b.icmp(ms_mir::ir::Cc::Eq, n, z);
                Ok(Val { v, own: false })
            }
            (TyKind::List(elem), "reversed") => self.list_reversed(recv, elem),
            (TyKind::List(elem), "take" | "drop") => {
                let sym = if name == "take" {
                    "msrt_list_take"
                } else {
                    "msrt_list_drop_n"
                };
                let d = self.type_desc(elem);
                let r = self.borrow(recv);
                let n = self.borrow(args[0].val);
                let out = self.call_runtime(sym, &[r, d, n], rty)?;
                Ok(Val { v: out, own: true })
            }
            (TyKind::List(elem), "get") => {
                let mut it = args.into_iter();
                let index = it.next().ok_or_else(|| Error::new("get without index"))?;
                self.list_get_or(recv, elem, index, it.next())
            }
            _ => Err(Error::new(format!(
                "unsupported native method {native} ({name})"
            ))),
        }
    }

    /// The written arguments of a native call in order; `wrapped` marks values meant for an `Optional` parameter.
    fn native_args(&mut self, view: &CallView<'_>) -> Result<Vec<NArg>, Error> {
        let mut out = Vec::new();
        for a in &view.arguments {
            let val = self.expr(a.expr)?;
            if self.dead {
                break;
            }
            out.push(NArg {
                name: a.slot.name,
                val,
                wrapped: a.wrap_optional.is_some(),
            });
        }
        Ok(out)
    }

    /// `(present, value)` operands of an optional `Int` argument for runtime calls.
    fn optional_int(&mut self, arg: Option<NArg>) -> Result<(Value, Value), Error> {
        match arg {
            None => Ok((self.b.bconst(false), self.b.iconst(0))),
            Some(a) if a.wrapped => Ok((self.b.bconst(true), self.borrow(a.val))),
            Some(_) => Err(Error::new(
                "optional argument passed through is not supported yet",
            )),
        }
    }

    /// The runtime descriptor of a type.
    pub fn type_desc(&mut self, t: MTy) -> Value {
        self.b
            .emit(
                ms_mir::ir::Op::TypeDesc,
                &[],
                ms_mir::ir::Imm::Ty(t),
                Some(MTy::PTR),
            )
            .expect("typedesc")
    }

    /// `xs.get(i, default:)`: negative indexes count from the end.
    fn list_get_or(
        &mut self,
        recv: Val,
        elem: MTy,
        index: NArg,
        default: Option<NArg>,
    ) -> Result<Val, Error> {
        let l = self.borrow(recv);
        let idx = self.borrow(index.val);
        let Some(default) = default else {
            let x = self.b.list_get(l, idx);
            return Ok(Val { v: x, own: false });
        };
        let n = self.b.list_len(l);
        let zero = self.b.iconst(0);
        let neg = self.b.icmp(ms_mir::ir::Cc::Lt, idx, zero);
        let shifted = self.b.binop(ms_mir::ir::Op::IAdd, idx, n);
        let i = self.b.select(neg, shifted, idx);
        let lo = self.b.icmp(ms_mir::ir::Cc::Ge, i, zero);
        let hi = self.b.icmp(ms_mir::ir::Cc::Lt, i, n);
        let ok = self.b.binop(ms_mir::ir::Op::And, lo, hi);
        let owned = self.needs_drop(elem);
        let out = self
            .b
            .declare_var(elem, if owned { Mode::Own } else { Mode::Borrow });
        let (hit, miss, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(ok, hit, &[], miss, &[]);
        self.b.seal_block(hit);
        self.b.seal_block(miss);
        self.b.switch_to(hit);
        let x = self.b.list_get(l, i);
        let xo = self.owned(Val { v: x, own: false });
        self.b.def_var(out, xo);
        self.b.br(join, &[]);
        self.b.switch_to(miss);
        let dv = if default.wrapped {
            default.val
        } else {
            let inner = self.b.opt_unwrap(default.val.v);
            Val {
                v: inner,
                own: false,
            }
        };
        let d = self.owned(dv);
        self.b.def_var(out, d);
        self.b.br(join, &[]);
        self.b.seal_block(join);
        self.b.switch_to(join);
        let r = self.b.use_var(out);
        Ok(Val { v: r, own: owned })
    }

    /// `xs.reversed()`: a fresh list read back to front.
    fn list_reversed(&mut self, recv: Val, elem: MTy) -> Result<Val, Error> {
        let l = self.borrow(recv);
        let n = self.b.list_len(l);
        let out = self.b.list_new(elem, n);
        let acc = self.b.declare_var(self.ty_of(out), Mode::Own);
        self.b.def_var(acc, out);
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        self.b.def_var(idx, n);
        let (header, body, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let zero = self.b.iconst(0);
        let c = self.b.icmp(ms_mir::ir::Cc::Gt, i, zero);
        self.b.br_if(c, body, &[], exit, &[]);
        self.b.seal_block(body);
        self.b.switch_to(body);
        let i = self.b.use_var(idx);
        let one = self.b.iconst(1);
        let j = self.b.binop(ms_mir::ir::Op::ISub, i, one);
        self.b.def_var(idx, j);
        let x = self.b.list_get(l, j);
        let xo = self.owned(Val { v: x, own: false });
        let cur = self.b.use_var(acc);
        let next = self.b.list_push(cur, xo);
        self.b.def_var(acc, next);
        self.b.br(header, &[]);
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        let r = self.b.use_var(acc);
        Ok(Val { v: r, own: true })
    }
}

/// One method of the stdout/stderr stream vtable.
fn build_stream_method(
    m: &mut ms_mir::ir::Module,
    name: &str,
    params: &[MTy],
    ret: MTy,
    stderr: bool,
) -> FuncId {
    let mut ps = vec![Param {
        ty: MTy::PTR,
        mode: Mode::Borrow,
    }];
    ps.extend(params.iter().map(|t| Param {
        ty: *t,
        mode: Mode::Borrow,
    }));
    let mut b = FuncBuilder::new(m, &format!("stream.{name}"), ps, ret);
    b.func_mut().kind = FuncKind::Method;
    b.func_mut().linkage = Linkage::Internal;
    let args = b.params();
    if name == "write" {
        let sym = if stderr {
            "msrt_io_write_stderr"
        } else {
            "msrt_io_write_stdout"
        };
        let ext = runtime_fn(b.m, sym, &[MTy::STR], MTy::UNIT);
        b.call_rt(ext, &[args[1]]);
    }
    match b.m.types.kind(ret).clone() {
        TyKind::Alt(a) => {
            let ok = b.m.alts[a.index()]
                .cases
                .iter()
                .position(|c| c.name == "ok")
                .unwrap_or(0) as u32;
            let u = b.unit();
            let r = b.alt_new(a, ok, &[u]);
            b.ret(Some(r));
        }
        _ => {
            let u = b.unit();
            b.ret(Some(u));
        }
    }
    let f = b.into_func();
    m.add_func(f)
}
