//! Standard-library natives: runtime calls and inline sequences.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::text::runtime_fn;
use ms_check::hir::{CallView, Resolution};
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

/// Loop body: `(index, element)` to an optional exit condition.
type ElementBody<'b, S> = dyn FnMut(&mut S, Value, Value) -> Result<Option<Value>, Error> + 'b;

/// A branch body producing an owned value, or `None` when it diverges.
type BranchBody<'b, S> = dyn FnMut(&mut S) -> Result<Option<Value>, Error> + 'b;

/// Builds one method of a native interface value from its name, parameters and result.
type MethodBuilder<'b> = dyn FnMut(&mut ms_mir::ir::Module, &str, &[MTy], MTy) -> FuncId + 'b;

/// Whether `name` is an `Optional` method lowered inline.
fn opt_method(name: &str) -> bool {
    matches!(
        name,
        "is_some" | "is_none" | "get" | "map" | "and_then" | "or_else" | "ok_or" | "ok_or_else"
    )
}

/// List methods that take a function and run it over the elements.
fn is_higher_order(name: &str) -> bool {
    matches!(
        name,
        "map" | "filter" | "count" | "some" | "every" | "for_each" | "find" | "find_index"
    )
}

/// The `module/name` of natives that bindings override with a bare name.
fn native_alias(native: &str) -> &str {
    match native {
        "sleep" => "time/sleep",
        other => other,
    }
}

/// An evaluated argument of a native call.
#[derive(Clone, Copy)]
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
        params: &[ct::Param],
    ) -> Result<Val, Error> {
        match native {
            "collections/range" => {
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let vals: Vec<Value> = args.iter().map(|a| self.borrow(a.val)).collect();
                let lt = self.emty(e)?;
                let v = self.call_runtime("msrt_list_range", &vals, lt)?;
                Ok(Val { v, own: true })
            }
            "panic" => {
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let m = self.borrow(args[0].val);
                let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
                    name: "msrt_fault_string".to_string(),
                    params: vec![Param {
                        ty: MTy::STR,
                        mode: Mode::Borrow,
                    }],
                    ret: MTy::UNIT,
                    noreturn: true,
                    pure_: false,
                });
                self.at(e.pos);
                self.b.call_rt(ext, &[m]);
                Ok(self.dummy(MTy::UNIT))
            }
            "io/stdout" => self.std_stream(e, false),
            "io/stderr" => self.std_stream(e, true),
            "time/clock" => self.time_clock(e, false),
            "time/wall_clock" => self.time_clock(e, true),
            other if other.starts_with("testing/") => {
                self.testing_native(e, view, &other["testing/".len()..])
            }
            other => {
                if !self.has_native_call(other) {
                    return Err(Error::new(format!("unsupported native function {other}")));
                }
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let result = self.emty(e)?;
                self.at(e.pos);
                self.native_call(other, params, &args, result)
            }
        }
    }

    /// Whether `native_call` lowers the native function `native`.
    fn has_native_call(&self, native: &str) -> bool {
        matches!(native, "math/min" | "math/max" | "time/duration")
            || crate::rtcall::function_symbol(native_alias(native)).is_some()
    }

    /// A native function applied to evaluated arguments (borrowed by the callee).
    pub(crate) fn native_call(
        &mut self,
        native: &str,
        params: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        if matches!(native, "math/min" | "math/max") {
            return self.min_max(native == "math/max", args);
        }
        if native == "time/duration" {
            return Ok(Val {
                v: self.borrow(args[0].val),
                own: false,
            });
        }
        let sym = crate::rtcall::function_symbol(native_alias(native))
            .ok_or_else(|| Error::new(format!("unsupported native function {native}")))?;
        self.rt_function(&sym, params, args, result)
    }

    /// `max(left, right)` / `min(left, right)`: `left` unless `right` is strictly greater
    /// (lesser). Floats order NaN above every other value.
    fn min_max(&mut self, max: bool, args: &[NArg]) -> Result<Val, Error> {
        use ms_mir::ir::{Cc, Op};
        let (left, right) = (self.borrow(args[0].val), self.borrow(args[1].val));
        let t = self.ty_of(left);
        // `a` ordered strictly above `b`.
        let (a, b) = if max { (right, left) } else { (left, right) };
        let above = if t == MTy::INT {
            self.b.icmp(Cc::Gt, a, b)
        } else if t == MTy::FLOAT {
            let gt = self.b.fcmp(Cc::Gt, a, b);
            let a_nan = self.b.fcmp(Cc::Ne, a, a);
            let b_num = self.b.fcmp(Cc::Eq, b, b);
            let nan_above = self.b.binop(Op::And, a_nan, b_num);
            self.b.binop(Op::Or, gt, nan_above)
        } else if t == MTy::STR {
            let c = self.call_runtime("msrt_string_compare", &[a, b], MTy::INT)?;
            let zero = self.b.iconst(0);
            self.b.icmp(Cc::Gt, c, zero)
        } else if let Some(sym) = self.ordering_symbol(t) {
            let c = self.call_runtime(sym, &[a, b], MTy::INT)?;
            let zero = self.b.iconst(0);
            self.b.icmp(Cc::Gt, c, zero)
        } else {
            return Err(Error::new(format!(
                "unsupported min/max on {}",
                ms_mir::print::ty_str(self.b.m, t)
            )));
        };
        if !self.needs_drop(t) {
            let v = self.b.select(above, right, left);
            return Ok(Val { v, own: false });
        }
        self.two_ways(
            above,
            t,
            &mut |s| {
                Ok(Some(s.owned(Val {
                    v: right,
                    own: false,
                })))
            },
            &mut |s| {
                Ok(Some(s.owned(Val {
                    v: left,
                    own: false,
                })))
            },
        )
    }

    /// `stdout()` / `stderr()`: an interface value over a MIR-built vtable.
    fn std_stream(&mut self, e: &Expr, stderr: bool) -> Result<Val, Error> {
        let name = if stderr { "stderr" } else { "stdout" };
        self.native_iface(e, name, &mut |m, method, params, ret| {
            build_stream_method(m, method, params, ret, stderr)
        })
    }

    /// `clock()` / `wall_clock()`: an interface whose `now` reads the runtime clock.
    fn time_clock(&mut self, e: &Expr, wall: bool) -> Result<Val, Error> {
        let name = if wall { "wall_clock" } else { "clock" };
        self.native_iface(e, name, &mut |m, method, params, ret| {
            build_clock_method(m, method, params, ret, wall)
        })
    }

    /// An interface value of the expression's type over a vtable of MIR-built methods.
    fn native_iface(
        &mut self,
        e: &Expr,
        name: &str,
        build: &mut MethodBuilder<'_>,
    ) -> Result<Val, Error> {
        let it = self.emty(e)?;
        let TyKind::Iface(iface) = self.b.m.types.kind(it).clone() else {
            return Err(Error::new(format!("{name}() is not an interface")));
        };
        let key = format!("vtable:{name}:{}", iface.0);
        let vt = match self.cx.vtables.get(&key) {
            Some(v) => *v,
            None => {
                let sigs = self.b.m.ifaces[iface.index()].methods.clone();
                let mut methods = Vec::new();
                for s in &sigs {
                    methods.push(build(self.b.m, &s.name, &s.params, s.ret));
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
        if native == "errors/message" {
            let concrete = self.ety(recv_expr);
            let data = self.ty_of(recv.v);
            let f = self
                .cx
                .native_method_fn(self.b.m, native, &concrete, data)?;
            let r = self.borrow(recv);
            let text = self.b.call(f, &[r]);
            return Ok(Val { v: text, own: true });
        }
        if let Some(v) = self.time_field(m, recv)? {
            return Ok(v);
        }
        if let Some(sym) = m
            .name()
            .and_then(|n| crate::rtcall::typed_method_symbol(&m.receiver, n.as_str()))
        {
            let result = self.emty(e)?;
            return self.rt_method(&sym, recv, &m.ty.params, &args, result);
        }
        let name = native.rsplit('/').next().unwrap_or(native);
        let rty = self.ty_of(recv.v);
        // `map_add`, `set_values`: the receiver type already says which.
        let name = if crate::mapset::is_map_or_set(self.b.m, rty) {
            name.strip_prefix("map_")
                .or_else(|| name.strip_prefix("set_"))
                .unwrap_or(name)
        } else {
            name
        };
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
            (TyKind::Obj(n, _), "length" | "is_empty") if n == "Map" || n == "Set" => {
                let r = self.borrow(recv);
                let len = self.call_runtime("msrt_map_length", &[r], MTy::INT)?;
                if name == "length" {
                    return Ok(Val { v: len, own: false });
                }
                let z = self.b.iconst(0);
                let v = self.b.icmp(ms_mir::ir::Cc::Eq, len, z);
                Ok(Val { v, own: false })
            }
            (TyKind::Obj(n, _), "get_or") if n == "Map" => {
                let result = self.emty(e)?;
                self.map_get_or(recv, &m.ty.params, &args, result)
            }
            (TyKind::Obj(n, _), "entries") if n == "Map" => {
                let result = self.emty(e)?;
                self.map_entries(recv_expr, recv, result)
            }
            (TyKind::List(_) | TyKind::Bytes, "length") => {
                let r = self.borrow(recv);
                let v = self.b.list_len(r);
                Ok(Val { v, own: false })
            }
            (TyKind::List(_) | TyKind::Bytes, "is_empty") => {
                let r = self.borrow(recv);
                let n = self.b.list_len(r);
                let z = self.b.iconst(0);
                let v = self.b.icmp(ms_mir::ir::Cc::Eq, n, z);
                Ok(Val { v, own: false })
            }
            (TyKind::List(elem), "reversed") => {
                let (lv, hidden) = self.list_source(recv_expr, recv)?;
                let r = self.list_reversed(lv, elem);
                self.release_source(lv, hidden);
                r
            }
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
            (TyKind::Int, "to_decimal") => {
                let n = self.borrow(recv);
                let result = self.emty(e)?;
                let v = self.call_runtime("msstd_decimal_from_int", &[n], result)?;
                Ok(Val { v, own: false })
            }
            (TyKind::Int, "to_float") => {
                let x = self.borrow(recv);
                let v = self
                    .b
                    .emit(
                        ms_mir::ir::Op::I2F,
                        &[x],
                        ms_mir::ir::Imm::None,
                        Some(MTy::FLOAT),
                    )
                    .expect("i2f");
                Ok(Val { v, own: false })
            }
            (TyKind::Float, "is_nan" | "is_finite") => {
                let x = self.borrow(recv);
                if name == "is_nan" {
                    let v = self.b.fcmp(ms_mir::ir::Cc::Ne, x, x);
                    return Ok(Val { v, own: false });
                }
                // `x - x` is zero for finite x and NaN for NaN and the infinities.
                let d = self.b.emit(
                    ms_mir::ir::Op::FSub,
                    &[x, x],
                    ms_mir::ir::Imm::None,
                    Some(MTy::FLOAT),
                );
                let zero = self.b.fconst(0.0);
                let v = self.b.fcmp(ms_mir::ir::Cc::Eq, d.expect("fsub"), zero);
                Ok(Val { v, own: false })
            }
            (_, "compare_int" | "compare_float") => {
                let a = self.borrow(recv);
                let b = self.borrow(args[0].val);
                let (lt, gt) = if name == "compare_int" {
                    (
                        self.b.icmp(ms_mir::ir::Cc::Lt, a, b),
                        self.b.icmp(ms_mir::ir::Cc::Gt, a, b),
                    )
                } else {
                    (
                        self.b.fcmp(ms_mir::ir::Cc::Lt, a, b),
                        self.b.fcmp(ms_mir::ir::Cc::Gt, a, b),
                    )
                };
                let (m1, one, zero) = (self.b.iconst(-1), self.b.iconst(1), self.b.iconst(0));
                let g = self.b.select(gt, one, zero);
                let v = self.b.select(lt, m1, g);
                Ok(Val { v, own: false })
            }
            (TyKind::Opt(inner), _) if opt_method(name) => {
                self.optional_method(e, name, recv, inner, args)
            }
            (TyKind::Alt(a), "get" | "err" | "or_else" | "map" | "and_then" | "to_optional") => {
                self.result_method(e, name, recv, a, args)
            }
            (TyKind::Alt(a), "is_ok" | "is_error") => {
                let want = if name == "is_ok" { "ok" } else { "error" };
                let case = self.b.m.alts[a.index()]
                    .cases
                    .iter()
                    .position(|c| c.name == want)
                    .ok_or_else(|| Error::new("Result without ok/error cases"))?;
                let r = self.borrow(recv);
                let tag = self.b.alt_tag(r);
                let k = self.b.iconst(case as i64);
                let v = self.b.icmp(ms_mir::ir::Cc::Eq, tag, k);
                Ok(Val { v, own: false })
            }
            (TyKind::List(_), "concat") => {
                let TyKind::List(elem) = self.b.m.types.kind(rty).clone() else {
                    unreachable!()
                };
                let d = self.type_desc(elem);
                let a = self.borrow(recv);
                let b = self.borrow(args[0].val);
                let out = self.call_runtime("msrt_list_concat", &[a, b, d], rty)?;
                Ok(Val { v: out, own: true })
            }
            (TyKind::Int, "to_string") if !args.is_empty() => {
                let (v, r) = (self.borrow(recv), self.borrow(args[0].val));
                let out = self.call_runtime("msrt_int_to_string_radix", &[v, r], MTy::STR)?;
                Ok(Val { v: out, own: true })
            }
            (_, "to_string") => self.format_value(recv),
            (_, "clone") => {
                let v = self.owned(Val {
                    v: recv.v,
                    own: false,
                });
                if recv.own {
                    self.drop_value(recv.v);
                }
                Ok(Val { v, own: true })
            }
            (TyKind::List(elem), "sorted") => {
                let f = args
                    .into_iter()
                    .next()
                    .ok_or_else(|| Error::new("sorted without comparator"))?;
                let ft = self.ty_of(f.val.v);
                let fvar = self.fresh_var(ft);
                let fo = self.owned(f.val);
                self.b.def_var(fvar, fo);
                let (lv, hidden) = self.list_source(recv_expr, recv)?;
                let r = self.list_sorted(lv, fvar, elem);
                self.release_source(lv, hidden);
                self.release_source(fvar, true);
                r
            }
            _ if crate::iterate::handles(self.b.m, rty, name) => {
                self.iterate_method(e, name, recv_expr, recv, args)
            }
            (TyKind::List(elem), _) if is_higher_order(name) => {
                let f = args
                    .into_iter()
                    .find(|a| self.is_fn(a.val.v))
                    .ok_or_else(|| Error::new("missing function argument"))?;
                let ft = self.ty_of(f.val.v);
                let fvar = self.fresh_var(ft);
                let fo = self.owned(f.val);
                self.b.def_var(fvar, fo);
                let out = self.emty(e)?;
                let (lv, hidden) = self.list_source(recv_expr, recv)?;
                let r = self.list_higher_order(name, lv, elem, fvar, out);
                self.release_source(lv, hidden);
                self.release_source(fvar, true);
                r
            }
            _ => {
                let Some(sym) = crate::rtcall::method_symbol(self.b.m, rty, native) else {
                    return Err(Error::new(format!(
                        "unsupported native method {native} ({name}) on {}",
                        ms_mir::print::ty_str(self.b.m, rty)
                    )));
                };
                let result = self.emty(e)?;
                self.rt_method(&sym, recv, &m.ty.params, &args, result)
            }
        }
    }

    /// A native method applied to evaluated arguments, for method values.
    pub(crate) fn bound_native_call(
        &mut self,
        m: &ct::MethodRef,
        recv: Val,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        if let Some(v) = self.time_field(m, recv)? {
            return Ok(v);
        }
        let rty = self.ty_of(recv.v);
        let name = m.name().map(|n| n.to_string()).unwrap_or_default();
        let sym = crate::rtcall::typed_method_symbol(&m.receiver, &name)
            .or_else(|| crate::rtcall::method_symbol(self.b.m, rty, m.native.as_str()))
            .ok_or_else(|| {
                Error::new(format!(
                    "unsupported native method value {} on {}",
                    m.native,
                    ms_mir::print::ty_str(self.b.m, rty)
                ))
            })?;
        self.rt_method(&sym, recv, &m.ty.params, args, result)
    }

    /// `Timestamp` and `Duration` accessors that read the representation directly.
    fn time_field(&mut self, m: &ct::MethodRef, recv: Val) -> Result<Option<Val>, Error> {
        let name = m.name().map(|n| n.to_string()).unwrap_or_default();
        if m.receiver.is_std("Duration") && name == "to_nanoseconds" {
            return Ok(Some(Val {
                v: self.borrow(recv),
                own: false,
            }));
        }
        let field = match name.as_str() {
            "unix_seconds" => 0,
            "nanoseconds" => 1,
            _ => return Ok(None),
        };
        if !m.receiver.is_std("Timestamp") {
            return Ok(None);
        }
        let TyKind::Rec(rid) = self.b.m.types.kind(self.ty_of(recv.v)).clone() else {
            return Err(Error::new("Timestamp is not a record"));
        };
        let r = self.borrow(recv);
        let v = self.b.rec_get(rid, field, r);
        Ok(Some(Val { v, own: false }))
    }

    /// A variable that always holds the receiver list, for use across loop headers.
    /// The flag says the variable is a hidden copy to drop afterwards.
    pub(crate) fn list_source(
        &mut self,
        recv_expr: &Expr,
        recv: Val,
    ) -> Result<(ms_mir::builder::Var, bool), Error> {
        if let Resolution::Local(b) = self.hir.resolution(recv_expr) {
            return Ok((self.local(&b)?.var, false));
        }
        let t = self.ty_of(recv.v);
        let var = self.fresh_var(t);
        let v = self.owned(recv);
        self.b.def_var(var, v);
        Ok((var, true))
    }

    pub(crate) fn release_source(&mut self, var: ms_mir::builder::Var, hidden: bool) {
        if hidden {
            let v = self.b.use_var(var);
            self.drop_value(v);
        }
    }

    /// A stable insertion sort of a copy, ordered by the comparator's sign.
    fn list_sorted(
        &mut self,
        lv: ms_mir::builder::Var,
        fvar: ms_mir::builder::Var,
        elem: MTy,
    ) -> Result<Val, Error> {
        use ms_mir::ir::{Cc, Op};
        let _ = elem;
        let l = self.b.use_var(lv);
        let n = self.b.list_len(l);
        let t = self.ty_of(l);
        let copy = self.owned(Val { v: l, own: false });
        let acc = self.b.declare_var(t, Mode::Own);
        self.b.def_var(acc, copy);
        let one = self.b.iconst(1);
        let zero = self.b.iconst(0);
        let i = self.b.declare_var(MTy::INT, Mode::Borrow);
        let j = self.b.declare_var(MTy::INT, Mode::Borrow);
        self.b.def_var(i, one);
        let oh = self.b.new_block();
        let ob = self.b.new_block();
        let ih = self.b.new_block();
        let ic = self.b.new_block();
        let sw = self.b.new_block();
        let on = self.b.new_block();
        let exit = self.b.new_block();
        self.b.br(oh, &[]);
        self.b.switch_to(oh);
        let iv = self.b.use_var(i);
        let c = self.b.icmp(Cc::Lt, iv, n);
        self.b.br_if(c, ob, &[], exit, &[]);
        self.b.seal_block(ob);
        self.b.switch_to(ob);
        let iv = self.b.use_var(i);
        self.b.def_var(j, iv);
        self.b.br(ih, &[]);
        self.b.switch_to(ih);
        let jv = self.b.use_var(j);
        let c = self.b.icmp(Cc::Gt, jv, zero);
        self.b.br_if(c, ic, &[], on, &[]);
        self.b.seal_block(ic);
        self.b.switch_to(ic);
        let jv = self.b.use_var(j);
        let prev = self.b.binop(Op::ISub, jv, one);
        let cur = self.b.use_var(acc);
        let a = self.b.list_get(cur, prev);
        let b = self.b.list_get(cur, jv);
        let f = self.b.use_var(fvar);
        let r = self.b.call_ind(f, &[a, b]);
        let gt = self.b.icmp(Cc::Gt, r, zero);
        self.b.br_if(gt, sw, &[], on, &[]);
        self.b.seal_block(sw);
        self.b.seal_block(on);
        self.b.switch_to(sw);
        let jv = self.b.use_var(j);
        let prev = self.b.binop(Op::ISub, jv, one);
        let cur = self.b.use_var(acc);
        let a = self.b.list_get(cur, prev);
        let b = self.b.list_get(cur, jv);
        let ac = self.owned(Val { v: a, own: false });
        let bc = self.owned(Val { v: b, own: false });
        let l1 = self.b.list_set(cur, prev, bc);
        let l2 = self.b.list_set(l1, jv, ac);
        self.b.def_var(acc, l2);
        self.b.def_var(j, prev);
        self.b.br(ih, &[]);
        self.b.seal_block(ih);
        self.b.switch_to(on);
        let iv = self.b.use_var(i);
        let next = self.b.binop(Op::IAdd, iv, one);
        self.b.def_var(i, next);
        self.b.br(oh, &[]);
        self.b.seal_block(oh);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        let r = self.b.use_var(acc);
        Ok(Val { v: r, own: true })
    }

    /// A collection method that changes its receiver place: the place receives the new value.
    pub fn mutator_call(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
        name: &str,
    ) -> Result<Val, Error> {
        // A map or set mutator returns its receiver; copy it only when something reads it.
        let discarded = self.discard == Some(e as *const Expr as usize);
        let result_ty = self.ety(e);
        let result_mty = self.emty(e)?;
        let hands_back = !discarded
            && (result_ty.is_std("List") || result_ty.is_std("Map") || result_ty.is_std("Set"));
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        if !self.is_place(recv_expr) {
            let x = self.expr(recv_expr)?;
            if self.dead {
                return Ok(x);
            }
            let old = self.owned(x);
            let (new, r) = self.mutate_any(name, old, &m.ty.params, &args, false, result_mty)?;
            return Ok(match r {
                Some(r) => {
                    self.drop_value(new);
                    r
                }
                None => Val { v: new, own: true },
            });
        }
        let mut result: Option<Val> = None;
        self.place_update(recv_expr, &mut |s, old| {
            let (new, r) = s.mutate_any(name, old, &m.ty.params, &args, hands_back, result_mty)?;
            result = r;
            Ok(new)
        })?;
        match result {
            Some(r) => Ok(r),
            None => {
                let u = self.b.unit();
                Ok(Val { v: u, own: false })
            }
        }
    }

    /// Runs two branches that each produce an owned value of `ty` (or diverge with `None`).
    pub(crate) fn two_ways(
        &mut self,
        cond: Value,
        ty: MTy,
        yes: &mut BranchBody<'_, Self>,
        no: &mut BranchBody<'_, Self>,
    ) -> Result<Val, Error> {
        let owned = self.needs_drop(ty);
        let out = self
            .b
            .declare_var(ty, if owned { Mode::Own } else { Mode::Borrow });
        let (a, b, join) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br_if(cond, a, &[], b, &[]);
        self.b.seal_block(a);
        self.b.seal_block(b);
        let mut live = false;
        self.enter(a);
        if let Some(v) = yes(self)? {
            self.b.def_var(out, v);
            self.b.br(join, &[]);
            live = true;
        }
        self.enter(b);
        if let Some(v) = no(self)? {
            self.b.def_var(out, v);
            self.b.br(join, &[]);
            live = true;
        }
        self.b.seal_block(join);
        self.enter(join);
        if !live {
            self.dead = true;
            return Ok(self.dummy(ty));
        }
        let v = self.b.use_var(out);
        Ok(Val { v, own: owned })
    }

    /// Drops an owned operand once its branch is done with it.
    fn finish(&mut self, x: Val) {
        if x.own && self.needs_drop(self.ty_of(x.v)) {
            self.drop_value(x.v);
        }
    }

    /// Faults unless `lo <= i && i < hi_exclusive` (`i` already resolved from the end).
    fn check_index(&mut self, op: i64, original: Value, i: Value, len: Value, allow_end: bool) {
        use ms_mir::ir::{Cc, Op};
        let zero = self.b.iconst(0);
        let lo = self.b.icmp(Cc::Ge, i, zero);
        let hi = self.b.icmp(if allow_end { Cc::Le } else { Cc::Lt }, i, len);
        let ok = self.b.binop(Op::And, lo, hi);
        let (good, bad) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(ok, good, &[], bad, &[]);
        self.b.seal_block(good);
        self.b.seal_block(bad);
        self.b.switch_to(bad);
        let opv = self.b.iconst(op);
        let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
            name: "msrt_list_index_fault".to_string(),
            params: vec![
                Param {
                    ty: MTy::INT,
                    mode: Mode::Borrow
                };
                3
            ],
            ret: MTy::UNIT,
            noreturn: true,
            pure_: false,
        });
        self.b.call_rt(ext, &[opv, original, len]);
        self.b.unreachable();
        self.b.switch_to(good);
    }

    /// `n.seconds`, `n.milliseconds`, `n.minutes`: nanoseconds, faulting beyond the range.
    pub(crate) fn duration_unit(&mut self, unit: &str, n: Val) -> Result<Val, Error> {
        use ms_mir::ir::{Cc, Op};
        let scale: i64 = match unit {
            "seconds" => 1_000_000_000,
            "milliseconds" => 1_000_000,
            _ => 60_000_000_000,
        };
        let v = self.borrow(n);
        let (lo, hi) = (i64::MIN / scale, i64::MAX / scale);
        let (lov, hiv) = (self.b.iconst(lo), self.b.iconst(hi));
        let ge = self.b.icmp(Cc::Ge, v, lov);
        let le = self.b.icmp(Cc::Le, v, hiv);
        let ok = self.b.binop(Op::And, ge, le);
        let (good, bad) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(ok, good, &[], bad, &[]);
        self.b.seal_block(good);
        self.b.seal_block(bad);
        self.b.switch_to(bad);
        let head = self.b.str_lit(&format!(
            "Int.{unit}: value must be between {lo} and {hi}, found "
        ));
        let found = self.call_runtime("msrt_int_to_string", &[v], MTy::STR)?;
        let msg = self.call_runtime("msrt_string_concat", &[head, found], MTy::STR)?;
        let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
            name: "msrt_fault_string".to_string(),
            params: vec![Param {
                ty: MTy::STR,
                mode: Mode::Borrow,
            }],
            ret: MTy::UNIT,
            noreturn: true,
            pure_: false,
        });
        self.b.call_rt(ext, &[msg]);
        self.b.unreachable();
        self.b.switch_to(good);
        let k = self.b.iconst(scale);
        let out = self.b.binop(Op::IMul, v, k);
        Ok(Val { v: out, own: false })
    }

    /// A fault with no operands (the runtime formats the message).
    fn runtime_fault(&mut self, sym: &str) {
        let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
            name: sym.to_string(),
            params: Vec::new(),
            ret: MTy::UNIT,
            noreturn: true,
            pure_: false,
        });
        self.b.call_rt(ext, &[]);
        self.b.unreachable();
    }

    fn optional_method(
        &mut self,
        e: &Expr,
        name: &str,
        recv: Val,
        inner: MTy,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let r = recv.v;
        let some = self.b.opt_is_some(r);
        match name {
            "is_some" | "is_none" => {
                let v = if name == "is_some" {
                    some
                } else {
                    self.b.unop(ms_mir::ir::Op::Not, some)
                };
                self.finish(recv);
                Ok(Val { v, own: false })
            }
            "get" => {
                let default = args.first().copied();
                self.two_ways(
                    some,
                    inner,
                    &mut |s| {
                        let p = s.b.opt_get(r);
                        let o = s.owned(Val { v: p, own: false });
                        s.finish(recv);
                        if let Some(d) = default {
                            s.finish(d.val);
                        }
                        Ok(Some(o))
                    },
                    &mut |s| match default {
                        Some(d) => {
                            let v = if d.wrapped {
                                s.owned(d.val)
                            } else {
                                let p = s.b.opt_unwrap(d.val.v);
                                let o = s.owned(Val { v: p, own: false });
                                s.finish(d.val);
                                o
                            };
                            s.finish(recv);
                            Ok(Some(v))
                        }
                        None => {
                            s.b.fault(ms_mir::ir::FaultKind::NoneUnwrap);
                            Ok(None)
                        }
                    },
                )
            }
            "map" | "and_then" | "or_else" => {
                let f = args
                    .first()
                    .copied()
                    .ok_or_else(|| Error::new("missing function"))?;
                let out = self.emty(e)?;
                let by_map = name == "map";
                let keep = name == "or_else";
                self.two_ways(
                    some,
                    out,
                    &mut |s| {
                        if keep {
                            let o = s.owned(Val { v: r, own: false });
                            s.finish(recv);
                            s.finish(f.val);
                            return Ok(Some(o));
                        }
                        let p = s.b.opt_get(r);
                        let fv = f.val.v;
                        let y = s.b.call_ind(fv, &[p]);
                        let v = if by_map { s.b.opt_some(y) } else { y };
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                    &mut |s| {
                        let v = if keep {
                            s.b.call_ind(f.val.v, &[])
                        } else {
                            s.none_owned(out)
                        };
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "ok_or" | "ok_or_else" => self.optional_ok_or(e, name, recv, args),
            _ => Err(Error::new(format!("unsupported Optional method {name}"))),
        }
    }

    /// `opt.ok_or(cause)` and `opt.ok_or_else(create)`.
    fn optional_ok_or(
        &mut self,
        e: &Expr,
        name: &str,
        recv: Val,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let r = recv.v;
        let some = self.b.opt_is_some(r);
        let out = self.emty(e)?;
        let TyKind::Alt(res) = self.b.m.types.kind(out).clone() else {
            return Err(Error::new("ok_or without a Result type"));
        };
        let index = |m: &ms_mir::ir::Module, n: &str| {
            m.alts[res.index()].cases.iter().position(|c| c.name == n)
        };
        let (ok, err) = (
            index(self.b.m, "ok").ok_or_else(|| Error::new("not a Result"))?,
            index(self.b.m, "error").ok_or_else(|| Error::new("not a Result"))?,
        );
        let cause = args.first().copied();
        let line = e.pos.line;
        let file = self.b.m.files[self.file as usize].clone();
        self.two_ways(
            some,
            out,
            &mut |s| {
                let p = s.b.opt_get(r);
                let o = s.owned(Val { v: p, own: false });
                s.finish(recv);
                if let Some(c) = cause {
                    s.finish(c.val);
                }
                Ok(Some(s.b.alt_new(res, ok as u32, &[o])))
            },
            &mut |s| {
                let failure = if name == "ok_or_else" {
                    let f = cause.ok_or_else(|| Error::new("ok_or_else without a function"))?;
                    let v = s.b.call_ind(f.val.v, &[]);
                    s.finish(f.val);
                    v
                } else if let Some(c) = cause {
                    if c.wrapped {
                        s.owned(c.val)
                    } else {
                        let p = s.b.opt_unwrap(c.val.v);
                        let o = s.owned(Val { v: p, own: false });
                        s.finish(c.val);
                        o
                    }
                } else {
                    // `MissingValue` names the source line of the call.
                    let et = s.b.m.alts[res.index()].cases[err].fields[0].1;
                    let TyKind::Alt(missing) = s.b.m.types.kind(et).clone() else {
                        return Err(Error::new("ok_or without a cause needs MissingValue"));
                    };
                    let base = file.rsplit('/').next().unwrap_or(&file);
                    let at = s.b.str_lit(&format!("{base}:{line}"));
                    let at = s.owned(Val { v: at, own: false });
                    s.b.alt_new(missing, 0, &[at])
                };
                s.finish(recv);
                Ok(Some(s.b.alt_new(res, err as u32, &[failure])))
            },
        )
    }

    fn result_method(
        &mut self,
        e: &Expr,
        name: &str,
        recv: Val,
        alt: ms_mir::types::AltId,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let case = |m: &ms_mir::ir::Module, n: &str| {
            m.alts[alt.index()].cases.iter().position(|c| c.name == n)
        };
        let ok = case(self.b.m, "ok").ok_or_else(|| Error::new("not a Result"))? as u32;
        let err = case(self.b.m, "error").ok_or_else(|| Error::new("not a Result"))? as u32;
        let r = recv.v;
        let tag = self.b.alt_tag(r);
        let k = self.b.iconst(ok as i64);
        let is_ok = self.b.icmp(ms_mir::ir::Cc::Eq, tag, k);
        let out = self.emty(e)?;
        let f = args.first().copied();
        match name {
            "get" => {
                let default = f;
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let p = s.b.alt_get(alt, ok, 0, r);
                        let o = s.owned(Val { v: p, own: false });
                        s.finish(recv);
                        if let Some(d) = default {
                            s.finish(d.val);
                        }
                        Ok(Some(o))
                    },
                    &mut |s| match default {
                        Some(d) => {
                            let v = if d.wrapped {
                                s.owned(d.val)
                            } else {
                                let p = s.b.opt_unwrap(d.val.v);
                                s.owned(Val { v: p, own: false })
                            };
                            s.finish(recv);
                            Ok(Some(v))
                        }
                        None => {
                            s.runtime_fault("msrt_fault_result_get");
                            Ok(None)
                        }
                    },
                )
            }
            "err" => self.two_ways(
                is_ok,
                out,
                &mut |s| {
                    s.runtime_fault("msrt_fault_result_err");
                    Ok(None)
                },
                &mut |s| {
                    let p = s.b.alt_get(alt, err, 0, r);
                    let o = s.owned(Val { v: p, own: false });
                    s.finish(recv);
                    Ok(Some(o))
                },
            ),
            "or_else" => {
                let f = f.ok_or_else(|| Error::new("missing function"))?;
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let p = s.b.alt_get(alt, ok, 0, r);
                        let o = s.owned(Val { v: p, own: false });
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(o))
                    },
                    &mut |s| {
                        let p = s.b.alt_get(alt, err, 0, r);
                        let v = s.b.call_ind(f.val.v, &[p]);
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "map" | "and_then" => {
                let f = f.ok_or_else(|| Error::new("missing function"))?;
                let TyKind::Alt(oa) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("Result method without Result result"));
                };
                let o_ok = case(self.b.m, "ok").unwrap_or(0) as u32;
                let o_err = case(self.b.m, "error").unwrap_or(1) as u32;
                let _ = (o_ok, o_err);
                let (out_ok, out_err) = {
                    let cs = &self.b.m.alts[oa.index()].cases;
                    (
                        cs.iter().position(|c| c.name == "ok").unwrap_or(0) as u32,
                        cs.iter().position(|c| c.name == "error").unwrap_or(1) as u32,
                    )
                };
                let is_map = name == "map";
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let p = s.b.alt_get(alt, ok, 0, r);
                        let y = s.b.call_ind(f.val.v, &[p]);
                        let v = if is_map {
                            s.b.alt_new(oa, out_ok, &[y])
                        } else {
                            y
                        };
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                    &mut |s| {
                        let p = s.b.alt_get(alt, err, 0, r);
                        let po = s.owned(Val { v: p, own: false });
                        let v = s.b.alt_new(oa, out_err, &[po]);
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "to_optional" => {
                let TyKind::Opt(_) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("to_optional without Optional result"));
                };
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let p = s.b.alt_get(alt, ok, 0, r);
                        let po = s.owned(Val { v: p, own: false });
                        let v = s.b.opt_some(po);
                        s.finish(recv);
                        Ok(Some(v))
                    },
                    &mut |s| {
                        let v = s.none_owned(out);
                        s.finish(recv);
                        Ok(Some(v))
                    },
                )
            }
            _ => Err(Error::new(format!("unsupported Result method {name}"))),
        }
    }

    /// A variable or a field chain from one.
    pub fn is_place(&self, e: &Expr) -> bool {
        let mut cur = e;
        while let ExprKind::Member { left, .. } = &cur.kind {
            cur = left;
        }
        matches!(&cur.kind, ExprKind::Name(_))
            && matches!(self.hir.resolution(cur), Resolution::Local(_))
    }

    fn mutate_any(
        &mut self,
        name: &str,
        old: Value,
        decl: &[ct::Param],
        args: &[NArg],
        copy_result: bool,
        result_ty: MTy,
    ) -> Result<(Value, Option<Val>), Error> {
        let runtime_only = !matches!(
            name,
            "append" | "set" | "prepend" | "insert" | "remove" | "pop" | "reverse_in_place"
        );
        let is_list = matches!(self.b.m.types.kind(self.ty_of(old)), TyKind::List(_));
        if !is_list || runtime_only {
            return self.mutate_rt(name, old, decl, args, copy_result, result_ty);
        }
        let (new, r) = self.mutate_list(name, old, args)?;
        if r.is_none() && copy_result {
            let v = self.owned(Val { v: new, own: false });
            return Ok((new, Some(Val { v, own: true })));
        }
        Ok((new, r))
    }

    /// `(new list, result)` of a list mutator applied to the owned `old` list.
    fn mutate_list(
        &mut self,
        name: &str,
        old: Value,
        args: &[NArg],
    ) -> Result<(Value, Option<Val>), Error> {
        use ms_mir::ir::{Cc, Op};
        let lt = self.ty_of(old);
        let TyKind::List(elem) = self.b.m.types.kind(lt).clone() else {
            return Err(Error::new("list mutator on a non-list"));
        };
        let d = self.type_desc(elem);
        match name {
            "append" => {
                let v = self.owned(args[0].val);
                Ok((self.b.list_push(old, v), None))
            }
            "set" => {
                let i = self.borrow(args[0].val);
                let n = self.b.list_len(old);
                let zero = self.b.iconst(0);
                let neg = self.b.icmp(Cc::Lt, i, zero);
                let shifted = self.b.binop(Op::IAdd, i, n);
                let r = self.b.select(neg, shifted, i);
                self.check_index(2, i, r, n, false);
                let v = self.owned(args[1].val);
                Ok((self.b.list_set(old, i, v), None))
            }
            "prepend" | "insert" | "remove" => {
                let n = self.b.list_len(old);
                let (idx, item) = match name {
                    "prepend" => (self.b.iconst(0), Some(args[0].val)),
                    "insert" => (self.borrow(args[0].val), Some(args[1].val)),
                    _ => (self.borrow(args[0].val), None),
                };
                let zero = self.b.iconst(0);
                let neg = self.b.icmp(Cc::Lt, idx, zero);
                let shifted = self.b.binop(Op::IAdd, idx, n);
                let i = self.b.select(neg, shifted, idx);
                if name != "prepend" {
                    self.check_index(
                        if item.is_some() { 0 } else { 1 },
                        idx,
                        i,
                        n,
                        item.is_some(),
                    );
                }
                let head = self.call_runtime("msrt_list_take", &[old, d, i], lt)?;
                let skip = if item.is_some() {
                    i
                } else {
                    let one = self.b.iconst(1);
                    self.b.binop(Op::IAdd, i, one)
                };
                let tail = self.call_runtime("msrt_list_drop_n", &[old, d, skip], lt)?;
                let mut mid = head;
                if let Some(x) = item {
                    let xo = self.owned(x);
                    let lit = self.b.list_lit(elem, &[xo]);
                    mid = self.call_runtime("msrt_list_concat", &[head, lit, d], lt)?;
                    self.drop_value(head);
                    self.drop_value(lit);
                }
                let out = self.call_runtime("msrt_list_concat", &[mid, tail, d], lt)?;
                self.drop_value(mid);
                self.drop_value(tail);
                self.drop_value(old);
                Ok((out, None))
            }
            "pop" => {
                let optty = self.b.m.types.opt(elem);
                let n = self.b.list_len(old);
                let zero = self.b.iconst(0);
                let empty = self.b.icmp(Cc::Eq, n, zero);
                let res = self.fresh_var(optty);
                let acc = self.fresh_var(lt);
                self.b.def_var(acc, old);
                let none = self.none_owned(optty);
                self.b.def_var(res, none);
                let (take, join) = (self.b.new_block(), self.b.new_block());
                self.b.br_if(empty, join, &[], take, &[]);
                self.b.seal_block(take);
                self.b.switch_to(take);
                let cur = self.b.use_var(acc);
                let one = self.b.iconst(1);
                let last = self.b.binop(Op::ISub, n, one);
                let x = self.b.list_get(cur, last);
                let xo = self.owned(Val { v: x, own: false });
                let some = self.b.opt_some(xo);
                self.b.def_var(res, some);
                let d2 = self.type_desc(elem);
                let rest = self.call_runtime("msrt_list_take", &[cur, d2, last], lt)?;
                self.drop_value(cur);
                self.b.def_var(acc, rest);
                self.b.br(join, &[]);
                self.b.seal_block(join);
                self.b.switch_to(join);
                let r = self.b.use_var(res);
                let l = self.b.use_var(acc);
                Ok((l, Some(Val { v: r, own: true })))
            }
            "reverse_in_place" => {
                let var = self.fresh_var(lt);
                self.b.def_var(var, old);
                let r = self.list_reversed(var, elem)?;
                let o = self.b.use_var(var);
                self.drop_value(o);
                Ok((r.v, None))
            }
            _ => Err(Error::new(format!("unsupported list mutator {name}"))),
        }
    }

    pub(crate) fn is_fn_value(&self, v: Value) -> bool {
        self.is_fn(v)
    }

    fn is_fn(&self, v: Value) -> bool {
        matches!(self.b.m.types.kind(self.ty_of(v)), TyKind::Fn(..))
    }

    /// A fresh SSA variable owning or borrowing per the type.
    pub(crate) fn fresh_var(&mut self, t: MTy) -> ms_mir::builder::Var {
        let owned = self.needs_drop(t);
        self.b
            .declare_var(t, if owned { Mode::Own } else { Mode::Borrow })
    }

    /// Visits each element with `body(index, element)`; a returned condition leaves the loop when true.
    fn each_element(
        &mut self,
        lv: ms_mir::builder::Var,
        body: &mut ElementBody<'_, Self>,
    ) -> Result<(), Error> {
        let l = self.b.use_var(lv);
        let n = self.b.list_len(l);
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        let zero = self.b.iconst(0);
        self.b.def_var(idx, zero);
        let (header, step, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let c = self.b.icmp(ms_mir::ir::Cc::Lt, i, n);
        self.b.br_if(c, step, &[], exit, &[]);
        self.b.seal_block(step);
        self.b.switch_to(step);
        let i = self.b.use_var(idx);
        let l = self.b.use_var(lv);
        let x = self.b.list_get(l, i);
        let stop = body(self, i, x)?;
        let one = self.b.iconst(1);
        let i = self.b.use_var(idx);
        let next = self.b.binop(ms_mir::ir::Op::IAdd, i, one);
        self.b.def_var(idx, next);
        match stop {
            Some(s) => {
                self.b.br_if(s, exit, &[], header, &[]);
            }
            None => self.b.br(header, &[]),
        }
        self.b.seal_block(header);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(())
    }

    fn list_higher_order(
        &mut self,
        name: &str,
        lv: ms_mir::builder::Var,
        elem: MTy,
        fvar: ms_mir::builder::Var,
        out: MTy,
    ) -> Result<Val, Error> {
        let l = self.b.use_var(lv);
        match name {
            "map" | "filter" => {
                let n = self.b.list_len(l);
                let res_elem = match self.b.m.types.kind(out).clone() {
                    TyKind::List(t) => t,
                    _ => return Err(Error::new("map without list result")),
                };
                let zero = self.b.iconst(0);
                let first = self
                    .b
                    .list_new(res_elem, if name == "map" { n } else { zero });
                let acc = self.fresh_var(out);
                self.b.def_var(acc, first);
                let is_map = name == "map";
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    if is_map {
                        let cur = s.b.use_var(acc);
                        let next = s.b.list_push(cur, r);
                        s.b.def_var(acc, next);
                        return Ok(None);
                    }
                    let (keep, skip) = (s.b.new_block(), s.b.new_block());
                    s.b.br_if(r, keep, &[], skip, &[]);
                    s.b.seal_block(keep);
                    s.b.seal_block(skip);
                    s.b.switch_to(keep);
                    let xo = s.owned(Val { v: x, own: false });
                    let cur = s.b.use_var(acc);
                    let next = s.b.list_push(cur, xo);
                    s.b.def_var(acc, next);
                    s.b.br(skip, &[]);
                    s.b.switch_to(skip);
                    Ok(None)
                })?;
                let r = self.b.use_var(acc);
                Ok(Val { v: r, own: true })
            }
            "count" => {
                let acc = self.b.declare_var(MTy::INT, Mode::Borrow);
                let z = self.b.iconst(0);
                self.b.def_var(acc, z);
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let cur = s.b.use_var(acc);
                    let one = s.b.iconst(1);
                    let zero = s.b.iconst(0);
                    let inc = s.b.select(r, one, zero);
                    let next = s.b.binop(ms_mir::ir::Op::IAdd, cur, inc);
                    s.b.def_var(acc, next);
                    Ok(None)
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: false,
                })
            }
            "some" | "every" => {
                let some = name == "some";
                let acc = self.b.declare_var(MTy::BOOL, Mode::Borrow);
                let init = self.b.bconst(!some);
                self.b.def_var(acc, init);
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let hit = if some {
                        r
                    } else {
                        s.b.unop(ms_mir::ir::Op::Not, r)
                    };
                    let t = s.b.bconst(some);
                    let cur = s.b.use_var(acc);
                    let next = s.b.select(hit, t, cur);
                    s.b.def_var(acc, next);
                    Ok(Some(hit))
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: false,
                })
            }
            "for_each" => {
                self.each_element(lv, &mut |s, _, x| {
                    {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    Ok(None)
                })?;
                let u = self.b.unit();
                Ok(Val { v: u, own: false })
            }
            "find" | "find_index" => {
                let by_index = name == "find_index";
                let acc = self.fresh_var(out);
                let none = self.none_owned(out);
                self.b.def_var(acc, none);
                self.each_element(lv, &mut |s, i, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let (hit, miss) = (s.b.new_block(), s.b.new_block());
                    s.b.br_if(r, hit, &[], miss, &[]);
                    s.b.seal_block(hit);
                    s.b.seal_block(miss);
                    s.b.switch_to(hit);
                    let payload = if by_index {
                        i
                    } else {
                        s.owned(Val { v: x, own: false })
                    };
                    let some = s.b.opt_some(payload);
                    s.b.def_var(acc, some);
                    s.b.br(miss, &[]);
                    s.b.switch_to(miss);
                    Ok(Some(r))
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: true,
                })
            }
            _ => Err(Error::new(format!(
                "unsupported list method {name} ({elem:?})"
            ))),
        }
    }

    /// The written arguments of a native call in order; `wrapped` marks values meant for an `Optional` parameter.
    pub(crate) fn native_args(&mut self, view: &CallView<'_>) -> Result<Vec<NArg>, Error> {
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
            Some(a) => {
                let v = self.borrow(a.val);
                let has = self.b.opt_is_some(v);
                let value = self.b.opt_get(v);
                Ok((has, value))
            }
        }
    }

    /// The runtime descriptor of a type.
    pub fn type_desc(&mut self, t: MTy) -> Value {
        self.cx.ensure_glue(self.b.m, t);
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
    fn list_reversed(&mut self, lv: ms_mir::builder::Var, elem: MTy) -> Result<Val, Error> {
        let l = self.b.use_var(lv);
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
        let l = self.b.use_var(lv);
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

/// A method of the clock vtable: `now` writes the reading through the runtime's out pointer.
fn build_clock_method(
    m: &mut ms_mir::ir::Module,
    name: &str,
    params: &[MTy],
    ret: MTy,
    wall: bool,
) -> FuncId {
    let mut ps = vec![Param {
        ty: MTy::PTR,
        mode: Mode::Borrow,
    }];
    ps.extend(params.iter().map(|t| Param {
        ty: *t,
        mode: Mode::Borrow,
    }));
    let mut b = FuncBuilder::new(m, &format!("clock.{name}"), ps, ret);
    b.func_mut().kind = FuncKind::Method;
    b.func_mut().linkage = Linkage::Internal;
    let sym = if wall {
        "msstd_time_wall_clock_now"
    } else {
        "msstd_time_clock_now"
    };
    let ext = runtime_fn(b.m, sym, &[], ret);
    let reading = b.call_rt(ext, &[]);
    b.ret(Some(reading));
    let f = b.into_func();
    m.add_func(f)
}
