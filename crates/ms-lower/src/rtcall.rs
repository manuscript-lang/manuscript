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

fn rt_sig(sym: &str) -> Option<RtSig> {
    for line in CATALOGUE.lines() {
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
    rt_sig(&sym).map(|_| sym)
}

/// Status codes of `ms-rt-abi` and the error cases they name.
const STATUS_CASES: [(i64, &str); 4] = [
    (1, "InvalidInput"),
    (2, "OutOfRange"),
    (3, "LimitExceeded"),
    (4, "InvalidData"),
];

impl FnLower<'_> {
    /// Calls the runtime function `sym` for a method call.
    pub(crate) fn rt_method(
        &mut self,
        sym: &str,
        recv: Val,
        decl: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let sig = rt_sig(sym).ok_or_else(|| Error::new(format!("no runtime symbol {sym}")))?;
        let mut inputs = vec![Input {
            val: Some(recv),
            wrapped: false,
        }];
        for p in decl {
            let a = args.iter().find(|a| a.name == p.name);
            inputs.push(Input {
                val: a.map(|a| a.val),
                wrapped: a.is_some_and(|a| a.wrapped),
            });
        }
        let recv_ty = self.ty_of(recv.v);
        let has_out = sig.params.last().is_some_and(|p| p.name == "out");
        let end = sig.params.len() - usize::from(has_out);
        let mut vals: Vec<Value> = Vec::new();
        let mut cursor = 0;
        let mut i = 0;
        while i < end {
            let p = &sig.params[i];
            match p.name.as_str() {
                "d" => {
                    let e = match self.b.m.types.kind(recv_ty).clone() {
                        TyKind::List(e) => e,
                        TyKind::Obj(_, a) if !a.is_empty() => a[0],
                        _ => return Err(Error::new(format!("{sym}: no element type"))),
                    };
                    vals.push(self.type_desc(e));
                }
                "kd" | "vd" => {
                    let TyKind::Obj(_, a) = self.b.m.types.kind(recv_ty).clone() else {
                        return Err(Error::new(format!("{sym}: not a map or set")));
                    };
                    let k = usize::from(p.name == "vd");
                    let t = *a
                        .get(k)
                        .ok_or_else(|| Error::new(format!("{sym}: no key/value type")))?;
                    vals.push(self.type_desc(t));
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
                    let v = self.borrow(x);
                    if p.ty == "*const u8" || p.ty == "*mut u8" {
                        // A generic element slot: pass the address of a copy in memory.
                        let t = self.ty_of(v);
                        let slot = self
                            .b
                            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
                            .expect("slot");
                        self.b.emit(Op::Store, &[slot, v], Imm::None, None);
                        vals.push(slot);
                    } else {
                        vals.push(v);
                    }
                }
            }
            i += 1;
        }
        self.finish_rt_call(sym, &sig, has_out, vals, result)
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

    fn finish_rt_call(
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
        let ret = direct(&sig.ret)
            .ok_or_else(|| Error::new(format!("{sym}: unsupported return {}", sig.ret)))?;
        if !has_out {
            if ret == MTy::BOOL && matches!(self.b.m.types.kind(result), TyKind::Alt(_)) {
                // A bare status: `Result[Unit, E]`.
                let status = self.call_runtime(sym, &vals, MTy::BOOL)?;
                return self.status_result(status, None, result);
            }
            let out = self.call_runtime(sym, &vals, ret)?;
            let owned = self.needs_drop(ret);
            return Ok(Val { v: out, own: owned });
        }
        if ret == MTy::UNIT {
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
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(payload), Some(MTy::PTR))
            .expect("slot");
        vals.push(slot);
        let status = self.call_runtime(sym, &vals, MTy::BOOL)?;
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
                &mut |s| Ok(Some(s.b.opt_none(result))),
            );
        }
        self.status_result(status, Some((slot, payload)), result)
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
        status: Value,
        out: Option<(Value, MTy)>,
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
        let code = self.b.unop(Op::B2I, status);
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
                Ok(Some(s.b.alt_new(a, ok as u32, &[payload])))
            },
            &mut |s| {
                let et = s.b.m.alts[a.index()].cases[err].fields[0].1;
                let TyKind::Alt(ea) = s.b.m.types.kind(et).clone() else {
                    return Err(Error::new("a runtime status needs an error alternative"));
                };
                let mut acc: Option<Value> = None;
                for (n, name) in STATUS_CASES {
                    let Some(idx) = s.b.m.alts[ea.index()]
                        .cases
                        .iter()
                        .position(|c| c.name == name)
                    else {
                        continue;
                    };
                    let cand = s.b.alt_new(ea, idx as u32, &[]);
                    acc = Some(match acc {
                        None => cand,
                        Some(prev) => {
                            let k = s.b.iconst(n);
                            let hit = s.b.icmp(Cc::Eq, code, k);
                            s.b.select(hit, cand, prev)
                        }
                    });
                }
                let e = acc.ok_or_else(|| Error::new("no error case for a runtime status"))?;
                Ok(Some(s.b.alt_new(a, err as u32, &[e])))
            },
        )
    }
}
