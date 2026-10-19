//! Calls into `ms-rt` driven by the declared signature of the symbol (`ms-rt/SYMBOLS.md`).
//!
//! The runtime ABI is regular (`ms-rt/ABI.md`, section 1): optional scalars flatten into
//! `has_x, x`, descriptors follow the receiver, constructed values and fallible results
//! come back through a trailing `out` pointer, and `u8` statuses name the error case. This
//! module marshals a call from the symbol's parameter names and types and the checked
//! signature of the language-level method.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_check::types as ct;
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::{Ty as MTy, TyKind};

const CATALOGUE: &str = include_str!("../../ms-rt/SYMBOLS.md");

/// One declared runtime parameter.
pub(crate) struct RtParam {
    pub name: String,
    pub ty: String,
}

/// A runtime function's parameters and return type (empty for none).
pub(crate) struct RtSig {
    pub params: Vec<RtParam>,
    pub ret: String,
}

const RENAMED: [(&str, &str); 2] = [
    ("process/arguments", "msrt_args"),
    ("collections/filled", "msrt_list_filled"),
];

/// The runtime symbol implementing the native function `native` (`module/name`).
pub(crate) fn function_symbol(native: &str) -> Option<String> {
    // Exports whose runtime name predates the `<module>_<name>` scheme.
    if let Some((_, sym)) = RENAMED.iter().find(|(n, _)| *n == native) {
        return Some((*sym).to_string());
    }
    let (module, name) = native.split_once('/')?;
    ["msrt", "msstd"]
        .iter()
        .map(|prefix| format!("{prefix}_{module}_{name}"))
        .find(|sym| rt_sig(sym).is_some())
}

pub(crate) fn rt_sig(sym: &str) -> Option<RtSig> {
    for line in CATALOGUE.lines() {
        // `msstd_math_sin (unary f64 -> f64)`: one `f64` in, one out.
        if line.strip_prefix(sym) == Some(" (unary f64 -> f64)") {
            return Some(RtSig {
                params: vec![RtParam {
                    name: "x".to_string(),
                    ty: "f64".to_string(),
                }],
                ret: "f64".to_string(),
            });
        }
        let Some(rest) = line.strip_prefix(sym).and_then(|r| r.strip_prefix('(')) else {
            continue;
        };
        let close = rest.rfind(')')?;
        let params = rest[..close]
            .split(',')
            .map(str::trim)
            .filter(|p| !p.is_empty())
            .filter_map(|p| {
                let (n, t) = p.split_once(':')?;
                Some(RtParam {
                    name: n.trim().to_string(),
                    ty: t.trim().to_string(),
                })
            })
            .collect();
        let ret = rest[close + 1..]
            .trim()
            .strip_prefix("->")
            .map(|r| r.trim().to_string())
            .unwrap_or_default();
        return Some(RtSig { params, ret });
    }
    None
}

/// A language-level argument of the call being marshalled.
#[derive(Clone, Copy)]
struct Input {
    val: Option<Val>,
    wrapped: bool,
}

/// The runtime symbol implementing a native method of a receiver type.
pub(crate) fn method_symbol(m: &ms_mir::ir::Module, recv: MTy, native: &str) -> Option<String> {
    let name = native.rsplit('/').next().unwrap_or(native);
    let name = match name {
        "format_int" => "to_string_radix",
        other => other,
    };
    let name = name
        .strip_prefix("map_")
        .or_else(|| name.strip_prefix("set_"))
        .unwrap_or(name);
    if let TyKind::Rec(rid) = m.types.kind(recv) {
        let record = m.records[rid.index()].name.as_str();
        if matches!(record, "Timestamp" | "Instant") {
            let name = native.rsplit('/').next().unwrap_or(native);
            let prefixed = format!("msstd_time_{}_{name}", record.to_lowercase());
            return [format!("msstd_time_{name}"), prefixed]
                .into_iter()
                .find(|sym| rt_sig(sym).is_some());
        }
    }
    // `time/duration_seconds` is `Duration.to_seconds`: the runtime spells the conversions out.
    if let Some(stem) = native.strip_prefix("time/") {
        let spelled = stem
            .split_once('_')
            .map(|(ty, rest)| format!("msstd_time_{ty}_to_{rest}"));
        let direct = format!("msstd_time_{stem}");
        return [Some(direct), spelled]
            .into_iter()
            .flatten()
            .find(|sym| rt_sig(sym).is_some());
    }
    if matches!(m.types.kind(recv), TyKind::Obj(n, _) if n == "BigInt") {
        let name = if name == "format" {
            "to_string_radix"
        } else {
            name
        };
        let sym = format!("msstd_bigint_{name}");
        return rt_sig(&sym).map(|_| sym);
    }
    let prefix = match m.types.kind(recv) {
        TyKind::Obj(n, _) if n == "Queue" => "queue",
        TyKind::Obj(n, _) if n == "PriorityQueue" => "priority_queue",
        TyKind::Str => "string",
        TyKind::List(_) => "list",
        TyKind::Bytes => "bytes",
        TyKind::Int => "int",
        TyKind::Float => "float",
        TyKind::Obj(n, _) if n == "Map" => "map",
        TyKind::Obj(n, _) if n == "Set" => "set",
        _ => return None,
    };
    let sym = format!("msrt_{prefix}_{name}");
    if rt_sig(&sym).is_some() {
        return Some(sym);
    }
    // A set is a map without values: it shares the map entry points.
    let name = if name == "values" { "keys" } else { name };
    let shared = format!("msrt_map_{name}");
    (prefix == "set")
        .then(|| rt_sig(&shared).map(|_| shared))
        .flatten()
}

/// Status codes of `ms-rt-abi` and the error cases they name. Status 11 (`Failed`) carries the
/// module's `failure_message` text when the error case has a `String` field.
const STATUS_CASES: [(i64, &str); 13] = [
    (1, "InvalidInput"),
    (2, "OutOfRange"),
    (3, "LimitExceeded"),
    (4, "InvalidData"),
    (5, "NotFound"),
    (6, "AlreadyExists"),
    (7, "NotEmpty"),
    (8, "PermissionDenied"),
    (9, "Unsupported"),
    (10, "Closed"),
    (11, "Failed"),
    (12, "Unavailable"),
    (13, "Timeout"),
];

/// `STATUS_NONE`: end of stream or an absent optional.
const STATUS_NONE: i64 = 16;

impl FnLower<'_> {
    /// Calls the runtime function `sym` for a method call.
    /// `Queue[T]()`, `Queue[T](capacity: n)` or `PriorityQueue[T](compare: f, capacity: n)`:
    /// a runtime queue of elements of `T`.
    pub(crate) fn construct_queue(
        &mut self,
        view: &ms_check::hir::CallView<'_>,
        ty: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Obj(name, args) = self.b.m.types.kind(ty).clone() else {
            return Err(Error::new("queue without an element type"));
        };
        let prioritized = name == "PriorityQueue";
        let desc = self.type_desc(args[0]);
        let mut compare = None;
        let mut capacity = None;
        for a in &view.arguments {
            let x = self.expr(a.expr)?;
            if self.dead {
                return Ok(self.dummy(ty));
            }
            if a.slot.name.as_str() == "compare" {
                compare = Some(x);
            } else {
                capacity = Some(Input {
                    val: Some(x),
                    wrapped: a.wrap_optional.is_some(),
                });
            }
        }
        let (has, cap) = match capacity {
            None => (self.b.bconst(false), self.b.iconst(0)),
            Some(input) => self.flatten_optional(input, "i64")?,
        };
        if !prioritized {
            let q = self.call_runtime("msrt_queue_new", &[desc, has, cap], ty)?;
            return Ok(Val { v: q, own: true });
        }
        let user = compare.ok_or_else(|| Error::new("PriorityQueue without a comparator"))?;
        let user = self.owned(user);
        let thunk = self.compare_closure(args[0], user);
        // The queue keeps its own reference to the comparator.
        let q = self.call_runtime("msrt_priority_queue_new", &[desc, thunk, has, cap], ty)?;
        self.drop_value(thunk);
        Ok(Val { v: q, own: true })
    }

    /// A closure the runtime calls as `code(closure, a, b)` with element slots, which loads
    /// both elements and calls the user comparator `user` (captured, consumed).
    fn compare_closure(&mut self, elem: MTy, user: Value) -> Value {
        use ms_mir::builder::FuncBuilder;
        use ms_mir::ir::{FuncKind, Mode, Param};
        let user_ty = self.ty_of(user);
        let key = format!("compare-thunk:{}", elem.0);
        let fty = self.b.m.types.func(vec![MTy::PTR, MTy::PTR], MTy::INT);
        let thunk = match self.cx.helpers.get(&key) {
            Some(t) => *t,
            None => {
                let ps = vec![
                    Param {
                        ty: MTy::PTR,
                        mode: Mode::Borrow,
                    },
                    Param {
                        ty: MTy::PTR,
                        mode: Mode::Borrow,
                    },
                    Param {
                        ty: MTy::PTR,
                        mode: Mode::Borrow,
                    },
                ];
                let mut b = FuncBuilder::new(self.b.m, "priority_queue.compare", ps, MTy::INT);
                b.func_mut().kind = FuncKind::Closure {
                    captures: vec![user_ty],
                };
                let p = b.params();
                let f = b
                    .emit(Op::ClosureCap, &[p[0]], Imm::Idx(0), Some(user_ty))
                    .expect("capture");
                let a = b
                    .emit(Op::Load, &[p[1]], Imm::Ty(elem), Some(elem))
                    .expect("load");
                let c = b
                    .emit(Op::Load, &[p[2]], Imm::Ty(elem), Some(elem))
                    .expect("load");
                let r = b.call_ind(f, &[a, c]);
                b.ret(Some(r));
                let func = b.into_func();
                let id = self.b.m.add_func(func);
                self.cx.helpers.insert(key, id);
                id
            }
        };
        self.b
            .emit(Op::ClosureNew, &[user], Imm::Func(thunk), Some(fty))
            .expect("closure")
    }

    pub(crate) fn rt_method(
        &mut self,
        sym: &str,
        recv: Val,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        self.rt_method_at(sym, recv, None, decl, args, result)
    }

    /// Like [`Self::rt_method`]; with `recv_ptr` the receiver parameter is that address, so
    /// the runtime changes the receiver in place.
    pub(crate) fn rt_method_at(
        &mut self,
        sym: &str,
        recv: Val,
        recv_ptr: Option<Value>,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        self.rt_call(sym, Some(recv), recv_ptr, decl, args, result)
    }

    /// Calls the runtime function `sym` for a call of a native function.
    pub(crate) fn rt_function(
        &mut self,
        sym: &str,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        self.rt_call(sym, None, None, decl, args, result)
    }

    fn rt_call(
        &mut self,
        sym: &str,
        recv: Option<Val>,
        recv_ptr: Option<Value>,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let sig = rt_sig(sym).ok_or_else(|| Error::new(format!("no runtime symbol {sym}")))?;
        let mut inputs = Vec::new();
        if let Some(r) = recv {
            inputs.push(Input {
                val: Some(r),
                wrapped: false,
            });
        }
        for p in decl {
            let a = args.iter().find(|a| a.name == p.name);
            inputs.push(Input {
                val: a.map(|a| a.val),
                wrapped: a.is_some_and(|a| a.wrapped),
            });
        }
        let recv_ty = recv.map(|r| self.ty_of(r.v));
        let has_out = sig.params.last().is_some_and(|p| p.name == "out");
        let end = sig.params.len() - usize::from(has_out);
        let mut vals: Vec<Value> = Vec::new();
        // Slots of borrowed owned values, taken back and dropped after the call.
        let mut lent: Vec<(Value, MTy)> = Vec::new();
        let mut cursor = 0;
        let mut i = 0;
        while i < end {
            let p = &sig.params[i];
            match p.name.as_str() {
                "d" => {
                    // A constructor such as `filled` has no receiver: its result names the element.
                    let mut recv_ty = recv_ty.unwrap_or(result);
                    if let TyKind::Alt(a) = self.b.m.types.kind(recv_ty).clone() {
                        let ok = self.ok_case_index(a)?;
                        recv_ty = self.b.m.alts[a.index()].cases[ok].fields[0].1;
                    }
                    let e = match self.b.m.types.kind(recv_ty).clone() {
                        TyKind::List(e) => e,
                        TyKind::Obj(_, a) if !a.is_empty() => a[0],
                        _ => return Err(Error::new(format!("{sym}: no element type"))),
                    };
                    vals.push(self.type_desc(e));
                }
                "kd" | "vd" => {
                    let recv_ty = recv_ty
                        .ok_or_else(|| Error::new(format!("{sym}: descriptor without receiver")))?;
                    let TyKind::Obj(_, a) = self.b.m.types.kind(recv_ty).clone() else {
                        return Err(Error::new(format!("{sym}: not a map or set")));
                    };
                    let k = usize::from(p.name == "vd");
                    match a.get(k) {
                        Some(t) => vals.push(self.type_desc(*t)),
                        // A set is a map without a value descriptor.
                        None if k == 1 => {
                            let ot = self.b.m.types.opt(MTy::STR);
                            vals.push(self.b.opt_none(ot));
                        }
                        None => return Err(Error::new(format!("{sym}: no key type"))),
                    }
                }
                n if n.starts_with("has_") && i + 1 < end => {
                    let input = *inputs
                        .get(cursor)
                        .ok_or_else(|| Error::new(format!("{sym}: missing argument")))?;
                    cursor += 1;
                    let payload = sig.params[i + 1].ty.as_str();
                    let (has, value) = self.flatten_optional(input, payload)?;
                    vals.push(has);
                    vals.push(value);
                    i += 1;
                }
                _ => {
                    let input = *inputs
                        .get(cursor)
                        .ok_or_else(|| Error::new(format!("{sym}: missing argument {}", p.name)))?;
                    if let (0, Some(ptr)) = (cursor, recv_ptr) {
                        cursor += 1;
                        vals.push(ptr);
                        i += 1;
                        continue;
                    }
                    cursor += 1;
                    let Some(x) = input.val else {
                        if p.ty.ends_with("StrObj") {
                            // An omitted optional string is a null pointer.
                            let ot = self.b.m.types.opt(MTy::STR);
                            vals.push(self.b.opt_none(ot));
                            i += 1;
                            continue;
                        }
                        return Err(Error::new(format!("{sym}: missing argument {}", p.name)));
                    };
                    // A `String` for a byte-vector parameter is encoded first.
                    let x = if p.ty.ends_with("VecVal") && self.ty_of(x.v) == MTy::STR {
                        let s = self.borrow(x);
                        let bytes = self.call_runtime("msrt_string_to_bytes", &[s], MTy::BYTES)?;
                        Val {
                            v: bytes,
                            own: true,
                        }
                    } else {
                        x
                    };
                    let consumed_aggregate = p.ty == "*mut VecVal" || p.ty == "*mut MapVal";
                    let clock = p.ty == "*const Timestamp" || p.ty == "*const Instant";
                    if p.ty == "*const u8" || p.ty == "*mut u8" || consumed_aggregate || clock {
                        // A generic element slot: pass the address of the value in memory.
                        // `*mut` hands the value over; `*const` is lent and taken back.
                        let x = if input.wrapped {
                            // The checker converted the argument to an optional element.
                            let o = self.owned(x);
                            let v = self.b.opt_some(o);
                            Val { v, own: true }
                        } else {
                            x
                        };
                        let t = self.ty_of(x.v);
                        let slot = self
                            .b
                            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
                            .expect("slot");
                        if self.needs_drop(t) {
                            let o = self.owned(x);
                            self.b.emit(Op::Put, &[slot, o], Imm::None, None);
                            if p.ty == "*const u8" {
                                lent.push((slot, t));
                            }
                        } else {
                            self.b.emit(Op::Store, &[slot, x.v], Imm::None, None);
                        }
                        vals.push(slot);
                    } else {
                        let v = self.borrow(x);
                        vals.push(v);
                    }
                }
            }
            i += 1;
        }
        let r = self.finish_rt_call(sym, &sig, has_out, vals, result)?;
        for (slot, t) in lent {
            let v = self
                .b
                .emit(Op::Take, &[slot], Imm::Ty(t), Some(t))
                .expect("take");
            self.drop_value(v);
        }
        Ok(r)
    }

    /// `(has, value)` runtime operands of an optional scalar argument.
    fn flatten_optional(&mut self, input: Input, payload: &str) -> Result<(Value, Value), Error> {
        let zero = |s: &mut Self| match payload {
            "i64" => s.b.iconst(0),
            "f64" => s.b.fconst(0.0),
            _ => s.b.bconst(false),
        };
        let Some(x) = input.val else {
            let (h, z) = (self.b.bconst(false), zero(self));
            return Ok((h, z));
        };
        if input.wrapped {
            let v = self.borrow(x);
            return Ok((self.b.bconst(true), v));
        }
        let v = self.borrow(x);
        if matches!(self.b.m.types.kind(self.ty_of(v)), TyKind::Opt(_)) {
            let has = self.b.opt_is_some(v);
            let value = self.b.opt_get(v);
            Ok((has, value))
        } else {
            Ok((self.b.bconst(true), v))
        }
    }

    pub(crate) fn finish_rt_call(
        &mut self,
        sym: &str,
        sig: &RtSig,
        has_out: bool,
        mut vals: Vec<Value>,
        result: MTy,
    ) -> Result<Val, Error> {
        let direct = |ret: &str| match ret {
            "i64" => Some(MTy::INT),
            "f64" => Some(MTy::FLOAT),
            "u8" => Some(MTy::BOOL),
            "*mut StrObj" | "*mut ms_rt_abi::StrObj" => Some(MTy::STR),
            "" | "()" => Some(MTy::UNIT),
            _ => None,
        };
        // A new runtime object (`BigInt`) is returned as its pointer.
        let object = sig.ret.starts_with("*mut ")
            && match self.b.m.types.kind(result) {
                TyKind::Obj(n, _) => n == "BigInt",
                TyKind::Iface(_) => sig.ret.starts_with("*mut Handle<"),
                _ => false,
            };
        let ret = direct(&sig.ret)
            .or(object.then_some(result))
            .ok_or_else(|| Error::new(format!("{sym}: unsupported return {}", sig.ret)))?;
        if !has_out {
            if ret == MTy::BOOL && matches!(self.b.m.types.kind(result), TyKind::Alt(_)) {
                // A bare status: `Result[Unit, E]`.
                let status = self.call_runtime(sym, &vals, MTy::BOOL)?;
                return self.status_result(sym, status, None, None, result);
            }
            if ret == MTy::STR && matches!(self.b.m.types.kind(result), TyKind::Alt(_)) {
                // A string that cannot fail: `Result[String, E]`.
                let text = self.call_runtime(sym, &vals, MTy::STR)?;
                let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
                    unreachable!()
                };
                let ok = self.ok_case_index(a)?;
                let v = self.b.alt_new(a, ok as u32, &[text]);
                return Ok(Val { v, own: true });
            }
            if ret == MTy::BOOL && result == MTy::UNIT {
                // A status the interface ignores: `Unit`.
                self.call_runtime(sym, &vals, MTy::BOOL)?;
                return Ok(Val {
                    v: self.b.unit(),
                    own: false,
                });
            }
            // A handle for a stream interface: `Subprocess.stdout()`.
            if sig.ret.starts_with("*mut Handle<")
                && let TyKind::Iface(i) = self.b.m.types.kind(result).clone()
            {
                let hir = self.hir.clone();
                let vt = self.cx.handle_vtable_of(self.b.m, &hir, sym, i)?;
                let ht = crate::natiface::handle_ty(self.b.m);
                let h = self.call_runtime(sym, &vals, ht)?;
                let v = self
                    .b
                    .emit(Op::IfaceNew, &[h], Imm::Vtable(vt), Some(result))
                    .expect("iface");
                return Ok(Val { v, own: true });
            }
            // A null string pointer is the absent `Optional[String]`.
            let ret = match self.b.m.types.kind(result) {
                TyKind::Opt(inner) if ret == MTy::STR && *inner == MTy::STR => result,
                _ => ret,
            };
            let out = self.call_runtime(sym, &vals, ret)?;
            let owned = self.needs_drop(ret);
            return Ok(Val { v: out, own: owned });
        }
        if ret == MTy::UNIT {
            if matches!(self.b.m.types.kind(result), TyKind::Str) {
                // A single pointer: the runtime stores it through the out pointer.
                let slot = self
                    .b
                    .emit(Op::Slot, &[], Imm::Ty(result), Some(MTy::PTR))
                    .expect("slot");
                vals.push(slot);
                self.call_runtime(sym, &vals, MTy::UNIT)?;
                let v = self
                    .b
                    .emit(Op::Take, &[slot], Imm::Ty(result), Some(result))
                    .expect("take");
                return Ok(Val { v, own: true });
            }
            // The constructed value returns through the trailing out pointer.
            let out = self.call_runtime(sym, &vals, result)?;
            return Ok(Val { v: out, own: true });
        }
        // A status (or presence flag) plus a value through `out`.
        let payload = match self.b.m.types.kind(result).clone() {
            TyKind::Alt(a) => {
                let ok = self.ok_case_index(a)?;
                self.b.m.alts[a.index()].cases[ok].fields[0].1
            }
            TyKind::Opt(t) => t,
            _ => return Err(Error::new(format!("{sym}: unexpected result type"))),
        };
        // `Result[Optional[T], E]`: the runtime writes a `T` and answers `STATUS_NONE` for none.
        let eof = match (self.b.m.types.kind(result), self.b.m.types.kind(payload)) {
            (TyKind::Alt(_), TyKind::Opt(inner)) => Some(*inner),
            _ => None,
        };
        // `Result[Interface, E]`: the runtime writes a handle, which the interface value wraps.
        let wrap = match (self.b.m.types.kind(result), self.b.m.types.kind(payload)) {
            (TyKind::Alt(_), TyKind::Iface(i)) => Some(*i),
            _ => None,
        };
        let slot_ty = match wrap {
            Some(_) => crate::natiface::handle_ty(self.b.m),
            None => eof.unwrap_or(payload),
        };
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(slot_ty), Some(MTy::PTR))
            .expect("slot");
        vals.push(slot);
        let status = self.call_runtime(sym, &vals, MTy::BOOL)?;
        if let Some(inner) = eof {
            return self.status_optional_result(sym, status, slot, inner, result);
        }
        let wrap = match wrap {
            Some(i) => {
                let hir = self.hir.clone();
                let vt = self.cx.handle_vtable_of(self.b.m, &hir, sym, i)?;
                Some((vt, payload))
            }
            None => None,
        };
        if matches!(self.b.m.types.kind(result), TyKind::Opt(_)) {
            return self.two_ways(
                status,
                result,
                &mut |s| {
                    let v =
                        s.b.emit(Op::Take, &[slot], Imm::Ty(payload), Some(payload))
                            .expect("take");
                    Ok(Some(s.b.opt_some(v)))
                },
                &mut |s| Ok(Some(s.none_owned(result))),
            );
        }
        self.status_result(sym, status, Some((slot, slot_ty)), wrap, result)
    }

    /// The error case of `ea` that the status `code` names; the last listed case otherwise.
    /// `failure` is the symbol returning the text of a `Failed` status.
    fn status_error(
        &mut self,
        ea: ms_mir::types::AltId,
        code: Value,
        cases: &[(i64, usize)],
        failure: Option<&str>,
    ) -> Result<Value, Error> {
        let (&(n, idx), rest) = cases
            .split_first()
            .ok_or_else(|| Error::new("no error case for a runtime status"))?;
        let build = |s: &mut Self| -> Result<Value, Error> {
            let carries_text = s.b.m.alts[ea.index()].cases[idx].fields.len() == 1;
            match failure {
                Some(sym) if n == 11 && carries_text => {
                    let text = s.call_runtime(sym, &[], MTy::STR)?;
                    Ok(s.b.alt_new(ea, idx as u32, &[text]))
                }
                // The module reports no failure text (a status this operation never returns).
                None if carries_text => {
                    let lit = s.b.str_lit("");
                    let text =
                        s.b.emit(Op::Copy, &[lit], Imm::None, Some(MTy::STR))
                            .expect("copy");
                    Ok(s.b.alt_new(ea, idx as u32, &[text]))
                }
                _ => Ok(s.b.alt_new(ea, idx as u32, &[])),
            }
        };
        if rest.is_empty() {
            return build(self);
        }
        let k = self.b.iconst(n);
        let hit = self.b.icmp(Cc::Eq, code, k);
        let ty = self.b.m.types.alt(ea);
        let r = self.two_ways(hit, ty, &mut |s| build(s).map(Some), &mut |s| {
            s.status_error(ea, code, rest, failure).map(Some)
        })?;
        Ok(r.v)
    }

    fn ok_case_index(&self, a: ms_mir::types::AltId) -> Result<usize, Error> {
        self.b.m.alts[a.index()]
            .cases
            .iter()
            .position(|c| c.name == "ok")
            .ok_or_else(|| Error::new("not a Result"))
    }

    /// The `error(..)` value of `result` for a nonzero runtime status `code`.
    fn status_failure(&mut self, result: MTy, code: Value, sym: &str) -> Result<Value, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a status needs a Result"));
        };
        let err = self.b.m.alts[a.index()]
            .cases
            .iter()
            .position(|c| c.name == "error")
            .ok_or_else(|| Error::new("not a Result"))?;
        let et = self.b.m.alts[a.index()].cases[err].fields[0].1;
        let TyKind::Alt(ea) = self.b.m.types.kind(et).clone() else {
            return Err(Error::new("a runtime status needs an error alternative"));
        };
        let cases: Vec<(i64, usize)> = STATUS_CASES
            .iter()
            .filter_map(|(n, name)| {
                let idx = self.b.m.alts[ea.index()]
                    .cases
                    .iter()
                    .position(|c| c.name == *name)?;
                Some((*n, idx))
            })
            .collect();
        let failure = failure_symbol(sym);
        let e = self.status_error(ea, code, &cases, failure.as_deref())?;
        Ok(self.b.alt_new(a, err as u32, &[e]))
    }

    /// `ok(value)` when the status is zero, else the error case the status names.
    fn status_result(
        &mut self,
        sym: &str,
        status: Value,
        out: Option<(Value, MTy)>,
        wrap: Option<(ms_mir::ir::VtableId, MTy)>,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a status needs a Result"));
        };
        let ok = self.ok_case_index(a)?;
        let code = self
            .b
            .emit(Op::B2I, &[status], Imm::None, Some(MTy::INT))
            .expect("b2i");
        let zero = self.b.iconst(0);
        let good = self.b.icmp(Cc::Eq, code, zero);
        self.two_ways(
            good,
            result,
            &mut |s| {
                let payload = match out {
                    Some((slot, t)) => {
                        s.b.emit(Op::Take, &[slot], Imm::Ty(t), Some(t))
                            .expect("take")
                    }
                    None => s.b.unit(),
                };
                let payload = match wrap {
                    Some((vt, it)) => {
                        s.b.emit(Op::IfaceNew, &[payload], Imm::Vtable(vt), Some(it))
                            .expect("iface")
                    }
                    None => payload,
                };
                Ok(Some(s.b.alt_new(a, ok as u32, &[payload])))
            },
            &mut |s| s.status_failure(result, code, sym).map(Some),
        )
    }

    /// `ok(some(value))` for status zero, `ok(none)` for `STATUS_NONE`, else the error the status names.
    fn status_optional_result(
        &mut self,
        sym: &str,
        status: Value,
        slot: Value,
        inner: MTy,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a status needs a Result"));
        };
        let ok = self.ok_case_index(a)?;
        let opt = self.b.m.alts[a.index()].cases[ok].fields[0].1;
        let code = self
            .b
            .emit(Op::B2I, &[status], Imm::None, Some(MTy::INT))
            .expect("b2i");
        let zero = self.b.iconst(0);
        let none = self.b.iconst(STATUS_NONE);
        let good = self.b.icmp(Cc::Eq, code, zero);
        let end = self.b.icmp(Cc::Eq, code, none);
        self.two_ways(
            good,
            result,
            &mut |s| {
                let v =
                    s.b.emit(Op::Take, &[slot], Imm::Ty(inner), Some(inner))
                        .expect("take");
                let some = s.b.opt_some(v);
                Ok(Some(s.b.alt_new(a, ok as u32, &[some])))
            },
            &mut |s| {
                let r = s.two_ways(
                    end,
                    result,
                    &mut |s| {
                        let n = s.none_owned(opt);
                        Ok(Some(s.b.alt_new(a, ok as u32, &[n])))
                    },
                    &mut |s| s.status_failure(result, code, sym).map(Some),
                )?;
                Ok(Some(r.v))
            },
        )
    }
}

/// The symbol returning the text of a `Failed` status of `sym`'s module, when it has one.
fn failure_symbol(sym: &str) -> Option<String> {
    let module = sym.strip_prefix("msstd_")?.split('_').next()?;
    let failure = format!("msstd_{module}_failure_message");
    rt_sig(&failure).map(|_| failure)
}
