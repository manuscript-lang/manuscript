//! Calls into `ms-rt` driven by the declared signature of the symbol (generated from the runtime sources).
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

/// Every exported runtime function with its parameters and return type, sorted by name. Generated
/// by `build.rs` from the exported items of `ms-rt` and the `ms-std-*` crates.
static SYMBOLS: &[RtEntry] = include!(concat!(env!("OUT_DIR"), "/rt_symbols.rs"));

/// A runtime function in the generated table: name, parameters as (name, type), return type.
type RtEntry = (
    &'static str,
    &'static [(&'static str, &'static str)],
    &'static str,
);

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

/// The runtime symbol implementing the native function `native` (`module/name`), as named by
/// `runtime_symbols` in `stdlib/bindings.json`.
pub(crate) fn function_symbol(native: &str) -> Option<String> {
    ms_check::stdlib::runtime_symbol(native).filter(|sym| rt_sig(sym).is_some())
}

pub(crate) fn rt_sig(sym: &str) -> Option<RtSig> {
    let at = SYMBOLS.binary_search_by_key(&sym, |s| s.0).ok()?;
    let (_, params, ret) = SYMBOLS[at];
    Some(RtSig {
        params: params
            .iter()
            .map(|(name, ty)| RtParam {
                name: (*name).to_string(),
                ty: (*ty).to_string(),
            })
            .collect(),
        ret: (*ret).to_string(),
    })
}

/// Whether a runtime function's result points into none of its borrowed arguments, so the
/// `lastuse` pass may drop an argument right after the call instead of keeping it alive as long
/// as the result. These string constructors return an owned buffer, an inline value or a
/// static (`ms-rt/src/string.rs`: `msrt_string_concat_val`, `concat_parts`, `msrt_string_append`,
/// `cloned`), never a view. Every other result is assumed to possibly borrow from an argument.
pub(crate) fn fresh_result(sym: &str) -> bool {
    matches!(
        sym,
        "msrt_string_concat" | "msrt_string_append" | "msrt_string_clone"
    ) || sym
        .strip_prefix("msrt_string_concat")
        .is_some_and(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
}

/// A language-level argument of the call being marshalled.
#[derive(Clone, Copy)]
pub(crate) struct Input {
    pub(crate) val: Option<Val>,
    /// The checker converted the argument to an optional element.
    pub(crate) wrapped: bool,
}

/// The runtime symbol implementing a native method of a receiver type.
pub(crate) fn method_symbol(m: &ms_mir::ir::Module, recv: MTy, native: &str) -> Option<String> {
    let name = native.rsplit('/').next().unwrap_or(native);
    let name = match name {
        "format_int" => "to_string_radix",
        "format_precision" => "to_precision",
        "format_exponential" => "to_exponential",
        "format_fixed" => "to_fixed",
        "format_float" => "to_string",
        "compare_int" | "compare_float" => "compare",
        other => other,
    };
    let name = match (m.types.kind(recv), name) {
        (TyKind::Str, "drop") => "drop_n",
        (TyKind::List(elem), "join") if matches!(m.types.kind(*elem), TyKind::Int) => "join_int",
        _ => name,
    };
    let name = name
        .strip_prefix("map_")
        .or_else(|| name.strip_prefix("set_"))
        .unwrap_or(name);
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
        TyKind::Str => "string",
        TyKind::List(_) => "list",
        TyKind::Bytes => "bytes",
        TyKind::Int | TyKind::Int8 | TyKind::Int16 | TyKind::Int32 => "int",
        TyKind::Float | TyKind::Float32 => "float",
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
const TYPED_NATIVES: &[(&str, &str)] = &[("Regex", "regex")];

/// The runtime symbol of `method` on a native type from [`TYPED_NATIVES`].
pub(crate) fn typed_method_symbol(recv: &ct::Ty, method: &str) -> Option<String> {
    let (ty, module) = TYPED_NATIVES.iter().find(|(t, _)| recv.is_std(t))?;
    let ty = ty.to_lowercase();
    ["msstd", "msrt"].iter().find_map(|prefix| {
        [
            format!("{prefix}_{module}_{ty}_{method}"),
            format!("{prefix}_{module}_{method}"),
        ]
        .into_iter()
        .find(|sym| rt_sig(sym).is_some())
    })
}

/// Status codes of `ms-rt-abi` and the error cases they name. Status 11 (`Failed`) carries the
/// module's `failure_message` text when the error case has a `String` field.
const STATUS_CASES: [(i64, &str); 16] = [
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
    (14, "OutputLimit"),
    (15, "NotTerminal"),
    (17, "Busy"),
];

/// `STATUS_NONE`: end of stream or an absent optional.
const STATUS_NONE: i64 = 16;

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

    /// `Map[Int, V]` and `Map[String, V]` lookups whose values are single words (`Int`, `Float`)
    /// go to the `_w8` / `_sw8` entry points, which probe a fixed slot layout without descriptor
    /// dispatch (`add` likewise). A `String` value is two words, so its maps take the general
    /// entry points: `find_w8` walks 24-byte slots and would read the wrong key.
    pub(crate) fn word_map_symbol(&self, sym: &str, map: MTy) -> Option<&'static str> {
        let TyKind::Obj(n, a) = self.b.m.types.kind(map) else {
            return None;
        };
        if n != "Map" || a.len() != 2 {
            return None;
        }
        let types = &self.b.m.types;
        let int_key = match types.kind(a[0]) {
            // Only the 8-byte slots of `Int`; packed widths go through descriptors.
            _ if a[0] == MTy::INT => true,
            TyKind::Str => false,
            _ => return None,
        };
        let scalar = a[1] == MTy::INT || a[1] == MTy::FLOAT;
        let word = scalar;
        match (sym, int_key) {
            ("msrt_map_add", true) if scalar => Some("msrt_map_add_w8"),
            ("msrt_map_add", false) if scalar => Some("msrt_map_add_sw8"),
            ("msrt_map_get_ptr", true) if word => Some("msrt_map_get_ptr_w8"),
            ("msrt_map_contains", true) if word => Some("msrt_map_contains_w8"),
            ("msrt_map_get", true) if scalar => Some("msrt_map_get_w8"),
            ("msrt_map_get_ptr", false) if word => Some("msrt_map_get_ptr_sw8"),
            ("msrt_map_contains", false) if word => Some("msrt_map_contains_sw8"),
            ("msrt_map_get", false) if scalar => Some("msrt_map_get_sw8"),
            _ => None,
        }
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
        let sym = recv
            .and_then(|r| self.word_map_symbol(sym, self.ty_of(r.v)))
            .unwrap_or(sym);
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
        // A trailing `err` receives the text of a `Failed` status, after any `out`.
        let body =
            sig.params.len() - usize::from(sig.params.last().is_some_and(|p| p.name == "err"));
        let has_out = sig.params[..body].last().is_some_and(|p| p.name == "out");
        let end = body - usize::from(has_out);
        let mut vals: Vec<Value> = Vec::new();
        // Slots of borrowed owned values, taken back and dropped after the call.
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
                        None if k == 1 => vals.push(self.b.iconst(0)),
                        None => return Err(Error::new(format!("{sym}: no key type"))),
                    }
                }
                n if n.starts_with("has_")
                    && i + 1 < end
                    && sig.params[i + 1].name.starts_with("has_")
                    && sig.params[i + 1].ty == "u8" =>
                {
                    // An optional record: its presence, then each field in turn.
                    let input = *inputs
                        .get(cursor)
                        .ok_or_else(|| Error::new(format!("{sym}: missing argument")))?;
                    cursor += 1;
                    i += 1 + self.flatten_optional_record(
                        input,
                        &sig.params[i + 1..end],
                        &mut vals,
                    )?;
                    continue;
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
                "src" => {
                    // The upload of a request: the closure the runtime reads chunks through.
                    let input = *inputs
                        .get(cursor)
                        .ok_or_else(|| Error::new(format!("{sym}: missing upload")))?;
                    cursor += 1;
                    let stream = input
                        .val
                        .ok_or_else(|| Error::new(format!("{sym}: missing upload")))?;
                    let env = self.upload_env(stream)?;
                    vals.push(env);
                }
                "env" => {
                    // The handler of a server: the closure the runtime calls per request.
                    let input = *inputs
                        .get(cursor)
                        .ok_or_else(|| Error::new(format!("{sym}: missing handler")))?;
                    cursor += 1;
                    let handler = input
                        .val
                        .ok_or_else(|| Error::new(format!("{sym}: missing handler")))?;
                    let env = self.handler_env(handler)?;
                    vals.push(env);
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
                        return Err(Error::new(format!("{sym}: missing argument {}", p.name)));
                    };
                    // An `HttpMethod` crosses as its token text.
                    let x = if p.name == "method"
                        && matches!(self.b.m.types.kind(self.ty_of(x.v)), TyKind::Alt(_))
                    {
                        self.method_text(x)?
                    } else {
                        x
                    };
                    // Payload-free alternatives (HashAlgorithm, Curve) cross the C ABI
                    // as their declaration-order case index, rather than their MIR value.
                    if p.ty == "i64"
                        && let TyKind::Alt(a) = self.b.m.types.kind(self.ty_of(x.v))
                        && self.b.m.alts[a.index()]
                            .cases
                            .iter()
                            .all(|c| c.fields.is_empty())
                    {
                        let v = self.borrow(x);
                        vals.push(self.b.alt_tag(v));
                        i += 1;
                        continue;
                    }
                    // A generic element slot takes the record whole, whatever its field is called.
                    let element = p.ty == "*const u8" || p.ty == "*mut u8";
                    if let Some(fields) = self.record_fields_named(x, &p.name).filter(|_| !element)
                    {
                        // A record argument crosses as its fields.
                        let TyKind::Rec(rid) = self.b.m.types.kind(self.ty_of(x.v)).clone() else {
                            unreachable!("record_fields_named found a record");
                        };
                        let rec = self.borrow(x);
                        for k in 0..fields {
                            let f = self.b.rec_get(rid, k as u32, rec);
                            vals.push(f);
                        }
                        i += fields;
                        continue;
                    }
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
                    // A record the runtime reads as a `repr(C)` struct of the same leaves.
                    let wire = p.ty.starts_with("*const ") && p.ty.ends_with("Wire");
                    if p.ty == "*const u8"
                        || p.ty == "*mut u8"
                        || consumed_aggregate
                        || clock
                        || wire
                    {
                        // A generic element slot: pass the address of the value in memory.
                        // `*mut` hands the value over; `*const` is lent.
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
                        if self.needs_drop(t) && p.ty.starts_with("*const ") {
                            // Only read by the runtime: lend the value itself.
                            let v = self.borrow(x);
                            self.b.emit(Op::Store, &[slot, v], Imm::None, None);
                        } else if self.needs_drop(t) {
                            let o = self.owned(x);
                            self.b.emit(Op::Put, &[slot, o], Imm::None, None);
                        } else {
                            self.b.emit(Op::Store, &[slot, x.v], Imm::None, None);
                        }
                        vals.push(slot);
                    } else {
                        let v = self.borrow(x);
                        let v = match self.b.m.types.kind(self.ty_of(v)).clone() {
                            // A budget that may be absent crosses as `i64::MAX` when it is.
                            TyKind::Opt(t) if p.ty == "i64" && t == MTy::INT => {
                                let has = self.b.opt_is_some(v);
                                let unlimited = self.b.iconst(i64::MAX);
                                let given = self.two_ways(
                                    has,
                                    MTy::INT,
                                    &mut |s| Ok(Some(s.b.opt_get(v))),
                                    &mut |_| Ok(Some(unlimited)),
                                )?;
                                given.v
                            }
                            // A present optional string arrives as the plain string.
                            _ => v,
                        };
                        vals.push(v);
                    }
                }
            }
            i += 1;
        }
        let r = self.finish_rt_call(sym, &sig, has_out, vals, result)?;
        Ok(r)
    }

    /// The field count of a record argument whose first field is the runtime parameter `name`.
    fn record_fields_named(&self, x: Val, name: &str) -> Option<usize> {
        let TyKind::Rec(rid) = self.b.m.types.kind(self.ty_of(x.v)) else {
            return None;
        };
        let fields = &self.b.m.records[rid.index()].fields;
        (fields.first()?.0 == name).then_some(fields.len())
    }

    /// Pushes `has_record` and the `(has, value)` pairs of the optional fields of an optional
    /// record argument, reading fields only when the record is present. Returns the number of
    /// runtime parameters used after the presence flag.
    pub(crate) fn flatten_optional_record(
        &mut self,
        input: Input,
        params: &[RtParam],
        vals: &mut Vec<Value>,
    ) -> Result<usize, Error> {
        let x = input.val;
        let held = x.map(|x| self.ty_of(x.v));
        // The checker may already have converted the argument to an optional element.
        let wrapped =
            input.wrapped || held.is_some_and(|t| matches!(self.b.m.types.kind(t), TyKind::Rec(_)));
        let rec_ty = held.and_then(|t| match self.b.m.types.kind(t).clone() {
            TyKind::Opt(t) if !wrapped => Some(t),
            TyKind::Rec(_) => Some(t),
            _ => None,
        });
        let fields = match rec_ty.map(|t| self.b.m.types.kind(t).clone()) {
            Some(TyKind::Rec(rid)) => self.b.m.records[rid.index()].fields.clone(),
            _ => Vec::new(),
        };
        let has = match x {
            Some(x) if wrapped => {
                let _ = x;
                self.b.bconst(true)
            }
            Some(x) => {
                let v = self.borrow(x);
                self.b.opt_is_some(v)
            }
            None => self.b.bconst(false),
        };
        vals.push(has);
        // A record to read fields from: the argument itself, or the empty record when the
        // optional is none (the fields are then ignored by the runtime).
        let mut blank_val = None;
        let view = match (x, rec_ty) {
            (Some(x), Some(rt)) => {
                let held = self.borrow(x);
                if wrapped {
                    Some(held)
                } else {
                    let TyKind::Rec(rid) = self.b.m.types.kind(rt).clone() else {
                        unreachable!("fields come from a record");
                    };
                    let mut empty = Vec::new();
                    for (_, ft) in &fields {
                        empty.push(self.none_owned(*ft));
                    }
                    let blank = self.b.rec_new(rid, &empty);
                    let some = self.b.opt_get(held);
                    blank_val = Some(blank);
                    Some(self.b.select(has, some, blank))
                }
            }
            _ => None,
        };
        let mut used = 0;
        let mut k = 0;
        // `params` begins at the first field's presence flag; pairs follow in field order.
        while used + 1 < params.len() && params[used].name.starts_with("has_") {
            let payload = params[used + 1].ty.as_str();
            let zero = |s: &mut Self| match payload {
                "i64" => s.b.iconst(0),
                "f64" => s.b.fconst(0.0),
                _ => s.b.bconst(false),
            };
            let (fh, fv) = match (view, fields.get(k)) {
                (Some(rec), Some(_)) => {
                    let TyKind::Rec(rid) = self
                        .b
                        .m
                        .types
                        .kind(rec_ty.expect("view has a type"))
                        .clone()
                    else {
                        unreachable!("fields come from a record");
                    };
                    let f = self.b.rec_get(rid, k as u32, rec);
                    (self.b.opt_is_some(f), self.b.opt_get(f))
                }
                _ => (self.b.bconst(false), zero(self)),
            };
            vals.push(fh);
            vals.push(fv);
            used += 2;
            k += 1;
        }
        // The runtime reads scalars only, so the empty record can go once they are out.
        if let Some(b) = blank_val {
            self.drop_value(b);
        }
        Ok(used)
    }

    /// `(has, value)` runtime operands of an optional scalar argument.
    pub(crate) fn flatten_optional(
        &mut self,
        input: Input,
        payload: &str,
    ) -> Result<(Value, Value), Error> {
        let zero = |s: &mut Self| match payload {
            "i64" => s.b.iconst(0),
            "f64" => s.b.fconst(0.0),
            // An absent string still passes a live (empty) string, which the runtime ignores.
            "*const StrVal" => s.b.str_lit(""),
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

    pub(crate) fn finish_rt_call(
        &mut self,
        sym: &str,
        sig: &RtSig,
        has_out: bool,
        vals: Vec<Value>,
        result: MTy,
    ) -> Result<Val, Error> {
        let r = self.finish_rt_call_inner(sym, sig, has_out, vals, result);
        self.err_slot = None;
        let mut r = r?;
        r.v = self.stamped(r.v)?;
        Ok(r)
    }

    /// Passes the slot a trailing `err` parameter writes the `Failed` text to.
    fn push_err_slot(&mut self, sig: &RtSig, vals: &mut Vec<Value>) {
        if sig.params.last().is_some_and(|p| p.name == "err") {
            let slot = self
                .b
                .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
                .expect("slot");
            vals.push(slot);
            self.err_slot = Some(slot);
        }
    }

    fn finish_rt_call_inner(
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
            "" | "()" => Some(MTy::UNIT),
            _ => None,
        };
        // A string comes back through a trailing `out: *mut StrVal` and no status.
        let body =
            sig.params.len() - usize::from(sig.params.last().is_some_and(|p| p.name == "err"));
        let string_ret = has_out
            && direct(&sig.ret) == Some(MTy::UNIT)
            && sig.params[..body]
                .last()
                .is_some_and(|p| p.ty == "*mut StrVal");
        let has_out = has_out && !string_ret;
        // A new runtime object (`BigInt`) is returned as its pointer.
        let object = sig.ret.starts_with("*mut ")
            && match self.b.m.types.kind(result) {
                TyKind::Obj(..) => true,
                TyKind::Iface(_) => is_handle_return(&sig.ret),
                _ => false,
            };
        let ret = direct(&sig.ret)
            .map(|r| if string_ret { MTy::STR } else { r })
            .or(object.then_some(result))
            .ok_or_else(|| Error::new(format!("{sym}: unsupported return {}", sig.ret)))?;
        if !has_out {
            if let (MTy::BOOL, TyKind::Alt(a)) = (ret, self.b.m.types.kind(result).clone())
                && self.ok_case_index(a).is_err()
            {
                // A payload-free enum returned as its case index.
                let raw = self.call_runtime(sym, &vals, MTy::INT)?;
                let mask = self.b.iconst(0xff);
                let code = self.b.binop(Op::And, raw, mask);
                let v = self.enum_from_index(a, code, 0)?;
                return Ok(Val { v, own: true });
            }
            if ret == MTy::BOOL && matches!(self.b.m.types.kind(result), TyKind::Alt(_)) {
                // A bare status: `Result[Unit, E]`.
                self.push_err_slot(sig, &mut vals);
                let code = self.status_code(sym, &vals)?;
                return self.status_result(sym, code, None, None, result);
            }
            if let (MTy::STR, TyKind::Alt(a)) = (ret, self.b.m.types.kind(result).clone())
                && self.ok_case_index(a).is_err()
            {
                // An `HttpMethod` returned as its token text.
                let text = self.call_runtime(sym, &vals, MTy::STR)?;
                let v = self.method_from_text(a, text, 0)?;
                self.drop_value(text);
                return Ok(Val { v, own: true });
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
            if is_handle_return(&sig.ret)
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
            let out = self.call_runtime(sym, &vals, ret)?;
            let owned = self.needs_drop(ret);
            return Ok(Val { v: out, own: owned });
        }
        if ret == MTy::UNIT {
            // The constructed value returns through the trailing out pointer.
            let out = self.call_runtime(sym, &vals, result)?;
            return Ok(Val { v: out, own: true });
        }
        // `InfoOut` is flat words that become a `FileInfo` record.
        if sig.params.last().is_some_and(|p| p.ty == "*mut InfoOut") {
            return self.finish_stat(sym, vals, result);
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
        self.push_err_slot(sig, &mut vals);
        // Statuses are read as `Int` (a `Bool` would make the optimizer assume 0 or 1).
        let is_result = matches!(self.b.m.types.kind(result), TyKind::Alt(_));
        let code = if is_result {
            Some(self.status_code(sym, &vals)?)
        } else {
            None
        };
        if let (Some(inner), Some(code)) = (eof, code) {
            let take = &mut |s: &mut Self| {
                Ok(s.b
                    .emit(Op::Take, &[slot], Imm::Ty(inner), Some(inner))
                    .expect("take"))
            };
            return self.status_optional_result(sym, code, take, result);
        }
        let wrap = match wrap {
            Some(i) => {
                let hir = self.hir.clone();
                let vt = self.cx.handle_vtable_of(self.b.m, &hir, sym, i)?;
                Some((vt, payload))
            }
            None => None,
        };
        let Some(code) = code else {
            // A presence flag.
            let status = self.call_runtime(sym, &vals, MTy::BOOL)?;
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
        };
        self.status_result(sym, code, Some((slot, slot_ty)), wrap, result)
    }

    /// The `u8` status a runtime function returns, as an `Int` (a `Bool` would make the
    /// optimizer assume 0 or 1). Only the low byte of the return register is defined.
    pub(crate) fn status_code(&mut self, sym: &str, vals: &[Value]) -> Result<Value, Error> {
        let raw = self.call_runtime(sym, vals, MTy::INT)?;
        let mask = self.b.iconst(0xff);
        Ok(self.b.binop(Op::And, raw, mask))
    }

    /// The payload-free cases of `ea` that runtime statuses name, as `(status, case index)`.
    pub(crate) fn status_cases(&self, ea: ms_mir::types::AltId) -> Vec<(i64, usize)> {
        STATUS_CASES
            .iter()
            .filter_map(|(n, name)| {
                let idx = self.b.m.alts[ea.index()]
                    .cases
                    .iter()
                    .position(|c| c.name == *name && c.fields.is_empty())?;
                Some((*n, idx))
            })
            .collect()
    }

    /// The error case of `ea` that the status `code` names; the last listed case otherwise.
    /// `failure` is the symbol returning the text of a `Failed` status.
    pub(crate) fn status_error(
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
                _ if carries_text && s.err_slot.is_some() => {
                    let slot = s.err_slot.expect("checked");
                    let text =
                        s.b.emit(Op::Take, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
                            .expect("take");
                    Ok(s.b.alt_new(ea, idx as u32, &[text]))
                }
                Some(sym) if n == 11 && carries_text => {
                    let text = s.call_runtime(sym, &[], MTy::STR)?;
                    Ok(s.b.alt_new(ea, idx as u32, &[text]))
                }
                // A `Failed(message)` of a module without a failure text.
                _ if carries_text => {
                    let text = s.lit("").v;
                    let text = s.owned(Val {
                        v: text,
                        own: false,
                    });
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

    /// The payload-free case of `a` whose index is `code`, trying cases from `from`.
    pub(crate) fn enum_from_index(
        &mut self,
        a: ms_mir::types::AltId,
        code: Value,
        from: usize,
    ) -> Result<Value, Error> {
        let last = self.b.m.alts[a.index()].cases.len() - 1;
        if from >= last {
            return Ok(self.b.alt_new(a, last as u32, &[]));
        }
        let k = self.b.iconst(from as i64);
        let hit = self.b.icmp(Cc::Eq, code, k);
        let ty = self.b.m.types.alt(a);
        let r = self.two_ways(
            hit,
            ty,
            &mut |s| Ok(Some(s.b.alt_new(a, from as u32, &[]))),
            &mut |s| s.enum_from_index(a, code, from + 1).map(Some),
        )?;
        Ok(r.v)
    }

    pub(crate) fn ok_case_index(&self, a: ms_mir::types::AltId) -> Result<usize, Error> {
        self.b.m.alts[a.index()]
            .cases
            .iter()
            .position(|c| c.name == "ok")
            .ok_or_else(|| Error::new("not a Result"))
    }

    /// The `error(..)` value of `result` for a nonzero runtime status `code`.
    pub(crate) fn status_failure(
        &mut self,
        result: MTy,
        code: Value,
        sym: &str,
    ) -> Result<Value, Error> {
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
        // Crypto uses status 6 for authentication failure (the shared host status
        // table uses it for AlreadyExists). Match the module's actual ABI.
        let statuses: &[(i64, &str)] = if sym.starts_with("msrt_crypto_") {
            &[
                (1, "InvalidInput"),
                (9, "Unsupported"),
                (6, "AuthenticationFailed"),
            ]
        } else {
            &STATUS_CASES
        };
        // A runtime that reports `Failed` text through `err` numbers the cases 1 + declaration
        // index (`ms-std-net/ABI.md`); the others share the `STATUS_CASES` codes.
        let cases: Vec<(i64, usize)> = if ordinal_status(sym) {
            (0..self.b.m.alts[ea.index()].cases.len())
                .map(|i| (i as i64 + 1, i))
                .collect()
        } else {
            statuses
                .iter()
                .filter_map(|(n, name)| {
                    let idx = self.b.m.alts[ea.index()]
                        .cases
                        .iter()
                        .position(|c| c.name == *name)?;
                    Some((*n, idx))
                })
                .collect()
        };
        let failure = failure_symbol(sym);
        let e = self.status_error(ea, code, &cases, failure.as_deref())?;
        Ok(self.b.alt_new(a, err as u32, &[e]))
    }

    /// `ok(value)` when the status is zero, else the error case the status names.
    pub(crate) fn status_result(
        &mut self,
        sym: &str,
        code: Value,
        out: Option<(Value, MTy)>,
        wrap: Option<(ms_mir::ir::VtableId, MTy)>,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a status needs a Result"));
        };
        let ok = self.ok_case_index(a)?;
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
    pub(crate) fn status_optional_result(
        &mut self,
        sym: &str,
        code: Value,
        take: &mut dyn FnMut(&mut Self) -> Result<Value, Error>,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("a status needs a Result"));
        };
        let ok = self.ok_case_index(a)?;
        let opt = self.b.m.alts[a.index()].cases[ok].fields[0].1;
        let zero = self.b.iconst(0);
        let none = self.b.iconst(STATUS_NONE);
        let good = self.b.icmp(Cc::Eq, code, zero);
        let end = self.b.icmp(Cc::Eq, code, none);
        self.two_ways(
            good,
            result,
            &mut |s| {
                let v = take(s)?;
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

/// Whether the statuses of `sym` number the error cases 1 + declaration index
/// (`ms-std-net/ABI.md`) instead of sharing the `STATUS_CASES` codes.
fn ordinal_status(sym: &str) -> bool {
    [
        "msrt_net_",
        "msrt_http_",
        "msrt_websocket_",
        "msrt_tls_",
        "msrt_pipe_",
        "extern:",
    ]
    .iter()
    .any(|p| sym.starts_with(p))
}

/// The symbol returning the text of a `Failed` status of `sym`'s module, when it has one.
fn failure_symbol(sym: &str) -> Option<String> {
    let module = sym.strip_prefix("msstd_")?.split('_').next()?;
    let failure = format!("msstd_{module}_failure_message");
    rt_sig(&failure).map(|_| failure)
}

/// Whether a runtime function returns a new runtime handle object for an interface value.
fn is_handle_return(ret: &str) -> bool {
    ret.starts_with("*mut Handle<") || ret == "*mut HasherObj"
}

#[cfg(test)]
mod tests {
    #[test]
    fn bound_runtime_symbols_are_catalogued() {
        ms_check::stdlib::ensure_standard();
        for path in ms_check::stdlib::standard_module_names() {
            for (_, sym) in ms_check::stdlib::standard_exports(path) {
                let native = sym.native.as_str();
                let Some(bound) = ms_check::stdlib::runtime_symbol(native) else {
                    continue;
                };
                assert!(
                    super::rt_sig(&bound).is_some(),
                    "{native} binds {bound}, which SYMBOLS.md does not list"
                );
            }
        }
    }

    /// Handle-backed receivers name their operations in the native identity, which must bind.
    #[test]
    fn handle_receiver_operations_have_runtime_symbols() {
        for (receiver, operations) in ms_check::receivers::RECEIVER_BINDINGS {
            if !matches!(*receiver, "IpAddress" | "Cidr" | "HttpHeaders") {
                continue;
            }
            for (name, native) in *operations {
                assert!(
                    super::function_symbol(native).is_some(),
                    "{receiver}.{name} ({native}) has no runtime_symbols entry"
                );
            }
        }
    }
}
