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
struct RtParam {
    name: String,
    ty: String,
}

/// A runtime function's parameters and return type (empty for none).
struct RtSig {
    params: Vec<RtParam>,
    ret: String,
}

/// The runtime symbol implementing the native function `native` (`module/name`).
pub(crate) fn function_symbol(native: &str) -> Option<String> {
    let (module, name) = native.split_once('/')?;
    let name = match (module, name) {
        ("http", "headers") => "headers_new",
        _ => name,
    };
    ["msrt", "msstd"]
        .iter()
        .map(|prefix| format!("{prefix}_{module}_{name}"))
        .find(|sym| rt_sig(sym).is_some())
}

fn rt_sig(sym: &str) -> Option<RtSig> {
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
    let prefix = match m.types.kind(recv) {
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

/// Native types whose methods are runtime symbols named after the type, and the module
/// they live in: `msstd_time_timestamp_shift`, `msrt_regex_matches`.
const TYPED_NATIVES: &[(&str, &str, &str)] = &[
    ("Timestamp", "time", "timestamp"),
    ("Instant", "time", "instant"),
    ("Duration", "time", "duration"),
    ("Regex", "regex", "regex"),
    ("Decimal", "decimal", "decimal"),
    ("IpAddress", "net", "ip_address"),
    ("Cidr", "net", "cidr"),
    ("HttpHeaders", "http", "headers"),
];

/// The runtime symbol of `method` on a native type from [`TYPED_NATIVES`].
pub(crate) fn typed_method_symbol(recv: &ct::Ty, method: &str) -> Option<String> {
    let (_, module, ty) = TYPED_NATIVES.iter().find(|(t, ..)| recv.is_std(t))?;
    ["msstd", "msrt"].iter().find_map(|prefix| {
        [
            format!("{prefix}_{module}_{ty}_{method}"),
            format!("{prefix}_{module}_{method}"),
        ]
        .into_iter()
        .find(|sym| rt_sig(sym).is_some())
    })
}

/// The output parameters that trail a runtime call.
enum Tail {
    None,
    /// `out`
    Out,
    /// `out, present`: an `Optional` payload.
    OutPresent,
    /// One output per field of a record payload, named after the fields.
    Fields(Vec<String>),
}

impl Tail {
    fn len(&self) -> usize {
        match self {
            Tail::None => 0,
            Tail::Out => 1,
            Tail::OutPresent => 2,
            Tail::Fields(n) => n.len(),
        }
    }
}

/// Where the runtime put the payload of a successful call.
enum OutKind {
    Unit,
    One(Value, MTy),
    Optional {
        slot: Value,
        inner: MTy,
        present: Value,
        opt: MTy,
    },
    Record {
        slots: Vec<(Value, MTy)>,
        rec: ms_mir::types::RecId,
    },
}

/// Status codes of `ms-rt-abi` and the error cases they name.
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
    (12, "Unavailable"),
    (13, "Timeout"),
    (14, "OutputLimit"),
];

impl FnLower<'_> {
    /// The list type of a call result: the result itself, or the `ok` payload of a `Result`.
    fn result_list(&self, result: MTy) -> Option<MTy> {
        let t = &*self.b.m;
        match t.types.kind(result) {
            TyKind::List(_) => Some(result),
            TyKind::Alt(a) => t.alts[a.index()]
                .cases
                .iter()
                .find(|c| c.name == "ok")
                .and_then(|c| c.fields.first())
                .map(|f| f.1)
                .filter(|f| matches!(t.types.kind(*f), TyKind::List(_))),
            _ => None,
        }
    }

    /// Calls the runtime function `sym` for a method call.
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
            inputs.push(Input { val: Some(r) });
        }
        for p in decl {
            let a = args.iter().find(|a| a.name == p.name);
            inputs.push(Input {
                val: a.map(|a| a.val),
            });
        }
        let recv_ty = recv.map(|r| self.ty_of(r.v));
        // `err` (the text of a `Failed(message)` case) trails `out` in the network natives.
        let has_err = indexed_status(sym) && sig.params.last().is_some_and(|p| p.name == "err");
        let body = sig.params.len() - usize::from(has_err);
        let tail = self.tail_of(&sig, body, result);
        let end = body - tail.len();
        let mut vals: Vec<Value> = Vec::new();
        // Slots of borrowed owned values, taken back and dropped after the call.
        let mut lent: Vec<(Value, MTy)> = Vec::new();
        let mut cursor = 0;
        let mut i = 0;
        while i < end {
            let p = &sig.params[i];
            match p.name.as_str() {
                "d" => {
                    // A function has no receiver: the descriptor is that of its list result.
                    let recv_ty = recv_ty
                        .or_else(|| self.result_list(result))
                        .ok_or_else(|| Error::new(format!("{sym}: descriptor without receiver")))?;
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
                    let consumed_aggregate = p.ty == "*mut VecVal" || p.ty == "*mut MapVal";
                    if p.ty == "*const u8" || p.ty == "*mut u8" || consumed_aggregate {
                        // A generic element slot: pass the address of the value in memory.
                        // `*mut` hands the value over; `*const` is lent and taken back.
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
                        // An enum crosses as its case index.
                        let v = if self.is_plain_enum(self.ty_of(v)) {
                            self.b.alt_tag(v)
                        } else {
                            v
                        };
                        vals.push(v);
                    }
                }
            }
            i += 1;
        }
        let r = self.finish_rt_call(sym, &sig, tail, has_err, vals, result)?;
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
        let v = self.borrow(x);
        let ty = self.ty_of(v);
        if let TyKind::Opt(inner) = self.b.m.types.kind(ty).clone() {
            let has = self.b.opt_is_some(v);
            if matches!(self.b.m.types.kind(inner), TyKind::Alt(_)) {
                // An enum crosses as its case index.
                let tag = self.two_ways(
                    has,
                    MTy::INT,
                    &mut |s| {
                        let p = s.b.opt_get(v);
                        Ok(Some(s.b.alt_tag(p)))
                    },
                    &mut |s| Ok(Some(s.b.iconst(0))),
                )?;
                return Ok((has, tag.v));
            }
            let value = self.b.opt_get(v);
            return Ok((has, value));
        }
        let value = if matches!(self.b.m.types.kind(ty), TyKind::Alt(_)) {
            self.b.alt_tag(v)
        } else {
            v
        };
        Ok((self.b.bconst(true), value))
    }

    fn finish_rt_call(
        &mut self,
        sym: &str,
        sig: &RtSig,
        tail: Tail,
        has_err: bool,
        mut vals: Vec<Value>,
        result: MTy,
    ) -> Result<Val, Error> {
        let has_out = !matches!(tail, Tail::None);
        let direct = |ret: &str| match ret {
            "i64" => Some(MTy::INT),
            "f64" => Some(MTy::FLOAT),
            "u8" => Some(MTy::BOOL),
            "*mut StrObj" | "*mut ms_rt_abi::StrObj" => Some(MTy::STR),
            "" | "()" => Some(MTy::UNIT),
            _ => None,
        };
        let handle_ret = sig.ret.ends_with("Obj") && !sig.ret.ends_with("StrObj");
        let ret = if handle_ret {
            self.handle_type(result)
        } else {
            direct(&sig.ret)
                .ok_or_else(|| Error::new(format!("{sym}: unsupported return {}", sig.ret)))?
        };
        if !has_out {
            if handle_ret {
                let h = self.call_runtime(sym, &vals, ret)?;
                return if ret == result {
                    Ok(Val { v: h, own: true })
                } else {
                    self.wrap_handle(h, result)
                };
            }
            if ret == MTy::BOOL && self.is_plain_enum(result) {
                // The case index of an enum.
                let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
                    unreachable!("plain enum")
                };
                let code = self.status_code(sym, &vals)?;
                let v = self.enum_from_tag(a, code, 0)?;
                return Ok(Val { v, own: false });
            }
            if ret == MTy::BOOL && matches!(self.b.m.types.kind(result), TyKind::Alt(_)) {
                // A bare status: `Result[Unit, E]`.
                let err = self.err_slot(has_err, &mut vals);
                let code = self.status_code(sym, &vals)?;
                return self.status_result(sym, code, OutKind::Unit, err, result);
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
        let out = match &tail {
            Tail::Out | Tail::None => {
                let slot_ty = self.handle_type(payload);
                let slot = self.slot(slot_ty);
                vals.push(slot);
                OutKind::One(slot, payload)
            }
            Tail::OutPresent => {
                let TyKind::Opt(inner) = self.b.m.types.kind(payload).clone() else {
                    return Err(Error::new(format!("{sym}: presence without an Optional")));
                };
                let slot = self.slot(inner);
                let present = self.slot(MTy::BOOL);
                vals.extend([slot, present]);
                OutKind::Optional {
                    slot,
                    inner,
                    present,
                    opt: payload,
                }
            }
            Tail::Fields(names) => {
                let TyKind::Rec(rid) = self.b.m.types.kind(payload).clone() else {
                    return Err(Error::new(format!("{sym}: fields without a record")));
                };
                let fields = self.b.m.records[rid.index()].fields.clone();
                let mut slots = vec![None; fields.len()];
                for n in names {
                    let idx = fields
                        .iter()
                        .position(|f| f.0 == *n)
                        .ok_or_else(|| Error::new(format!("{sym}: no field {n}")))?;
                    let slot = self.slot(fields[idx].1);
                    vals.push(slot);
                    slots[idx] = Some((slot, fields[idx].1));
                }
                let slots = slots
                    .into_iter()
                    .collect::<Option<Vec<_>>>()
                    .ok_or_else(|| Error::new(format!("{sym}: a record field has no output")))?;
                OutKind::Record { slots, rec: rid }
            }
        };
        if matches!(self.b.m.types.kind(result), TyKind::Alt(_)) {
            let err = self.err_slot(has_err, &mut vals);
            let code = self.status_code(sym, &vals)?;
            return self.status_result(sym, code, out, err, result);
        }
        // A presence flag.
        let OutKind::One(slot, _) = out else {
            return Err(Error::new(format!("{sym}: unsupported result shape")));
        };
        let status = self.call_runtime(sym, &vals, MTy::BOOL)?;
        self.two_ways(
            status,
            result,
            &mut |s| {
                let v =
                    s.b.emit(Op::Take, &[slot], Imm::Ty(payload), Some(payload))
                        .expect("take");
                Ok(Some(s.b.opt_some(v)))
            },
            &mut |s| Ok(Some(s.none_owned(result))),
        )
    }

    /// Whether `t` is an enum: an alternative whose cases carry no fields and that is no `Result`.
    fn is_plain_enum(&self, t: MTy) -> bool {
        let TyKind::Alt(a) = self.b.m.types.kind(t) else {
            return false;
        };
        let cases = &self.b.m.alts[a.index()].cases;
        !cases.is_empty() && cases.iter().all(|c| c.fields.is_empty() && c.name != "none")
    }

    /// The case of the enum `a` whose index is `tag`.
    fn enum_from_tag(
        &mut self,
        a: ms_mir::types::AltId,
        tag: Value,
        i: usize,
    ) -> Result<Value, Error> {
        let n = self.b.m.alts[a.index()].cases.len();
        if i + 1 == n {
            return Ok(self.b.alt_new(a, i as u32, &[]));
        }
        let k = self.b.iconst(i as i64);
        let hit = self.b.icmp(Cc::Eq, tag, k);
        let ty = self.b.m.types.alt(a);
        let r = self.two_ways(
            hit,
            ty,
            &mut |s| Ok(Some(s.b.alt_new(a, i as u32, &[]))),
            &mut |s| s.enum_from_tag(a, tag, i + 1).map(Some),
        )?;
        Ok(r.v)
    }

    /// A zero-initialised stack slot for a value of `t`.
    fn slot(&mut self, t: MTy) -> Value {
        self.b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot")
    }

    /// The trailing output parameters of the first `body` parameters of `sig`.
    fn tail_of(&self, sig: &RtSig, body: usize, result: MTy) -> Tail {
        let name = |i: usize| sig.params[i].name.as_str();
        if body >= 2 && name(body - 1) == "present" && name(body - 2) == "out" {
            return Tail::OutPresent;
        }
        if body >= 1 && name(body - 1) == "out" {
            return Tail::Out;
        }
        // A record result whose fields are filled one by one: `data`, `sender`.
        let payload = match self.b.m.types.kind(result) {
            TyKind::Alt(a) => self.b.m.alts[a.index()]
                .cases
                .iter()
                .find(|c| c.name == "ok")
                .and_then(|c| c.fields.first())
                .map(|f| f.1),
            _ => None,
        };
        if let Some(TyKind::Rec(rid)) = payload.map(|p| self.b.m.types.kind(p).clone()) {
            let fields = &self.b.m.records[rid.index()].fields;
            let n = (0..body)
                .rev()
                .take_while(|i| fields.iter().any(|f| f.0 == name(*i)))
                .count();
            if n > 0 {
                return Tail::Fields(
                    (body - n..body)
                        .map(|i| sig.params[i].name.clone())
                        .collect(),
                );
            }
        }
        Tail::None
    }

    /// The `u8` status a runtime function returns, as an `Int` (a `Bool` would make the
    /// optimizer assume 0 or 1). Only the low byte of the return register is defined.
    fn status_code(&mut self, sym: &str, vals: &[Value]) -> Result<Value, Error> {
        let raw = self.call_runtime(sym, vals, MTy::INT)?;
        let mask = self.b.iconst(0xff);
        Ok(self.b.binop(Op::And, raw, mask))
    }

    /// The error case of `ea` that the status `code` names; the last listed case otherwise.
    fn status_error(
        &mut self,
        ea: ms_mir::types::AltId,
        code: Value,
        cases: &[(i64, usize)],
    ) -> Result<Value, Error> {
        let (&(n, idx), rest) = cases
            .split_first()
            .ok_or_else(|| Error::new("no error case for a runtime status"))?;
        if rest.is_empty() {
            return Ok(self.b.alt_new(ea, idx as u32, &[]));
        }
        let k = self.b.iconst(n);
        let hit = self.b.icmp(Cc::Eq, code, k);
        let ty = self.b.m.types.alt(ea);
        let r = self.two_ways(
            hit,
            ty,
            &mut |s| Ok(Some(s.b.alt_new(ea, idx as u32, &[]))),
            &mut |s| s.status_error(ea, code, rest).map(Some),
        )?;
        Ok(r.v)
    }

    /// The value the runtime stored through its output slots.
    fn take_out(&mut self, out: &OutKind) -> Result<Value, Error> {
        match out {
            OutKind::Unit => Ok(self.b.unit()),
            OutKind::One(slot, t) => {
                let ht = self.handle_type(*t);
                let v = self
                    .b
                    .emit(Op::Take, &[*slot], Imm::Ty(ht), Some(ht))
                    .expect("take");
                Ok(if ht == *t { v } else { self.wrap_handle(v, *t)?.v })
            }
            OutKind::Optional {
                slot,
                inner,
                present,
                opt,
            } => {
                let flag = self
                    .b
                    .emit(Op::Load, &[*present], Imm::Ty(MTy::BOOL), Some(MTy::BOOL))
                    .expect("load");
                let (slot, inner, opt) = (*slot, *inner, *opt);
                let r = self.two_ways(
                    flag,
                    opt,
                    &mut |s| {
                        let v = s
                            .b
                            .emit(Op::Take, &[slot], Imm::Ty(inner), Some(inner))
                            .expect("take");
                        Ok(Some(s.b.opt_some(v)))
                    },
                    &mut |s| Ok(Some(s.none_owned(opt))),
                )?;
                Ok(r.v)
            }
            OutKind::Record { slots, rec } => {
                let mut fields = Vec::new();
                for (slot, t) in slots {
                    fields.push(
                        self.b
                            .emit(Op::Take, &[*slot], Imm::Ty(*t), Some(*t))
                            .expect("take"),
                    );
                }
                Ok(self.b.rec_new(*rec, &fields))
            }
        }
    }

    /// The type a runtime handle has before it is wrapped as `t` (`t` itself unless an interface).
    fn handle_type(&mut self, t: MTy) -> MTy {
        match self.b.m.types.kind(t).clone() {
            TyKind::Iface(i) if self.cx.is_handle_iface(i) => self.cx.handle_ty(self.b.m, i),
            _ => t,
        }
    }

    /// The out slot for the text of a `Failed(message)` case, when the symbol has one.
    fn err_slot(&mut self, has_err: bool, vals: &mut Vec<Value>) -> Option<Value> {
        if !has_err {
            return None;
        }
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
            .expect("slot");
        vals.push(slot);
        Some(slot)
    }

    /// The error case whose declaration index is `code - 1`; a case with a text field takes
    /// the message the runtime stored through `err`.
    fn indexed_error(
        &mut self,
        ea: ms_mir::types::AltId,
        code: Value,
        err_slot: Option<Value>,
        i: usize,
    ) -> Result<Value, Error> {
        let cases = self.b.m.alts[ea.index()].cases.clone();
        let fields: Vec<MTy> = cases[i].fields.iter().map(|f| f.1).collect();
        let mut build = move |s: &mut Self| -> Result<Option<Value>, Error> {
            let mut payload = Vec::new();
            for t in &fields {
                if *t != MTy::STR {
                    return Err(Error::new("an error case field must be text"));
                }
                payload.push(match err_slot {
                    Some(slot) => s
                        .b
                        .emit(Op::Take, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
                        .expect("take"),
                    // The symbol never reports this case without a message slot.
                    None => {
                        let lit = s.b.str_lit("");
                        s.b.emit(Op::Copy, &[lit], Imm::None, Some(MTy::STR))
                            .expect("copy")
                    }
                });
            }
            Ok(Some(s.b.alt_new(ea, i as u32, &payload)))
        };
        if i + 1 == cases.len() {
            return Ok(build(self)?.expect("case"));
        }
        let k = self.b.iconst(i as i64 + 1);
        let hit = self.b.icmp(Cc::Eq, code, k);
        let ty = self.b.m.types.alt(ea);
        let r = self.two_ways(hit, ty, &mut build, &mut |s| {
            s.indexed_error(ea, code, err_slot, i + 1).map(Some)
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

    /// `ok(value)` when the status is zero, else the error case the status names.
    fn status_result(
        &mut self,
        sym: &str,
        code: Value,
        out: OutKind,
        err_slot: Option<Value>,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a status needs a Result"));
        };
        let ok = self.ok_case_index(a)?;
        let err = self.b.m.alts[a.index()]
            .cases
            .iter()
            .position(|c| c.name == "error")
            .ok_or_else(|| Error::new("not a Result"))?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(Cc::Eq, code, zero);
        self.two_ways(
            good,
            result,
            &mut |s| {
                let payload = s.take_out(&out)?;
                Ok(Some(s.b.alt_new(a, ok as u32, &[payload])))
            },
            &mut |s| {
                let et = s.b.m.alts[a.index()].cases[err].fields[0].1;
                let TyKind::Alt(ea) = s.b.m.types.kind(et).clone() else {
                    return Err(Error::new("a runtime status needs an error alternative"));
                };
                if indexed_status(sym) {
                    let e = s.indexed_error(ea, code, err_slot, 0)?;
                    return Ok(Some(s.b.alt_new(a, err as u32, &[e])));
                }
                let cases: Vec<(i64, usize)> = STATUS_CASES
                    .iter()
                    .filter_map(|(n, name)| {
                        let idx = s.b.m.alts[ea.index()]
                            .cases
                            .iter()
                            .position(|c| c.name == *name && c.fields.is_empty())?;
                        Some((*n, idx))
                    })
                    .collect();
                let e = s.status_error(ea, code, &cases)?;
                Ok(Some(s.b.alt_new(a, err as u32, &[e])))
            },
        )
    }
}

/// Whether a runtime symbol reports `1 + the declaration index` of an error case rather than
/// an `ms-rt-abi` status (the network modules, `ms-std-net/ABI.md`).
fn indexed_status(sym: &str) -> bool {
    ["msrt_net_", "msrt_tls_", "msrt_http_", "msrt_websocket_"]
        .iter()
        .any(|p| sym.starts_with(p))
}
