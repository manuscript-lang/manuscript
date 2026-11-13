//! Calls into `ms-rt` driven by the declared signature of the symbol (generated from the runtime sources).
//!
//! The runtime ABI is regular (`ms-rt/ABI.md`, section 1): optional scalars flatten into
//! `has_x: HasRaw, x`, descriptors follow the receiver, constructed values and fallible results
//! come back through a trailing `out` pointer, and `u8` statuses name the error case. This
//! module marshals a call from the symbol's parameter names and types and the checked
//! signature of the language-level method.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::native::NArg;
use ms_check::api::types as ct;
use ms_mir::ir::{Cc, Imm, Op, Value};
use ms_mir::types::Native;
use ms_mir::types::{Ty as MTy, TyKind};

/// Every exported runtime function with its parameters and return type, sorted by name. Generated
/// by `build.rs` from the exported items of `ms-rt` and the `ms-std-*` crates.
static SYMBOLS: &[RtEntry] = include!(concat!(env!("OUT_DIR"), "/rt_symbols.rs"));

/// A runtime function in the generated table: name, parameters as (name, type, is a handle, is a
/// kept function value),
/// return type and flag bits.
type RtEntry = (
    &'static str,
    &'static [(&'static str, &'static str, bool, bool)],
    &'static str,
    u8,
    &'static str,
    &'static str,
);

/// The ABI facts a runtime function declares with a `// ms:` comment in its source
/// (`cargo xtask symbols` types them in `rt_symbols.txt`).
#[derive(Clone, Copy, Default)]
pub(crate) struct RtFlags {
    /// Never reaches a cancellation point.
    pub leaf: bool,
    /// Only reads memory and cannot fault or run user code.
    pub reads: bool,
    /// The result borrows none of the arguments.
    pub fresh: bool,
    /// Starts a task that runs code of the program (`// ms: spawns`).
    pub spawns: bool,
    /// Has a `<name>_take` twin that reuses the first argument when it dies at the call
    /// (`// ms: takes_self`).
    pub takes_self: bool,
    /// The MIR instruction (`// ms: op=<mnemonic>`) the function is on its arguments.
    pub op: Option<&'static str>,
    /// How its failures name their domain (`//! ms: domain` of its file, or `domain=`).
    pub domain: Option<&'static str>,
}

/// The declared flags of the runtime function `sym` (none for an unknown symbol).
pub(crate) fn rt_flags(sym: &str) -> RtFlags {
    let Ok(at) = SYMBOLS.binary_search_by_key(&sym, |s| s.0) else {
        return RtFlags::default();
    };
    let (_, _, _, bits, op, domain) = SYMBOLS[at];
    RtFlags {
        leaf: bits & 1 != 0,
        reads: bits & 2 != 0,
        fresh: bits & 4 != 0,
        spawns: bits & 16 != 0,
        takes_self: bits & 32 != 0,
        op: (!op.is_empty()).then_some(op),
        domain: (!domain.is_empty()).then_some(domain),
    }
}

/// Whether the runtime function `sym` takes ownership of its parameter `i`: a function value an
/// extern keeps after it returns (the checker moving_params the argument; the runtime drops it once).
pub(crate) fn hands_over(sym: &str, i: usize) -> bool {
    rt_sig(sym).is_some_and(|sig| sig.params.get(i).is_some_and(|p| p.closure))
}

/// One declared runtime parameter.
pub(crate) struct RtParam {
    pub name: String,
    pub ty: String,
    /// Declared as a runtime handle object (`ObjCell<T>`) rather than a value.
    pub handle: bool,
    /// Declared `// ms: keeps:<param>`: a function value the runtime stores and drops itself.
    pub closure: bool,
}

impl RtSig {
    /// Whether the function returns a new runtime handle object.
    pub(crate) fn returns_handle(&self) -> bool {
        self.ret_handle
    }
}

impl RtParam {
    /// Whether this parameter is a runtime handle object rather than a value.
    pub(crate) fn is_handle(&self) -> bool {
        self.handle
    }
}

/// A runtime function's parameters and return type (empty for none).
pub(crate) struct RtSig {
    pub params: Vec<RtParam>,
    pub ret: String,
    pub ret_handle: bool,
}

/// Bodiless natives the runtime implements directly, with their symbol. The loop lowering recognises `range` by its
/// native identity, so it stays a declaration instead of a wrapper over an extern.
const GENERIC_NATIVES: &[(&str, &str)] = &[("collections/range", "msrt_list_range")];

pub(crate) fn function_symbol(native: &str) -> Option<String> {
    let (_, sym) = GENERIC_NATIVES.iter().find(|(n, _)| *n == native)?;
    rt_sig(sym).map(|_| (*sym).to_string())
}

pub(crate) fn rt_sig(sym: &str) -> Option<RtSig> {
    let at = SYMBOLS.binary_search_by_key(&sym, |s| s.0).ok()?;
    let (_, params, ret, bits, _, _) = SYMBOLS[at];
    Some(RtSig {
        params: params
            .iter()
            .map(|(name, ty, handle, closure)| RtParam {
                name: (*name).to_string(),
                ty: (*ty).to_string(),
                handle: *handle,
                closure: *closure,
            })
            .collect(),
        ret: (*ret).to_string(),
        ret_handle: bits & 8 != 0,
    })
}

/// Whether a runtime function's result points into none of its borrowed arguments, so the
/// `lastuse` pass may drop an argument right after the call instead of keeping it alive as long
/// as the result. The runtime function declares it (`// ms: fresh`); every other result is
/// assumed to possibly borrow from an argument.
pub(crate) fn fresh_result(sym: &str) -> bool {
    rt_flags(sym).fresh
}

/// The role of the runtime function `sym` for passes and code generation. This table is the one
/// place lowering names those functions; passes read the role from the extern.
pub(crate) fn extern_role(sym: &str) -> ms_mir::ir::ExternRole {
    use ms_mir::ir::ExternRole as R;
    match sym {
        "msrt_strbuilder_append" => R::StrBuilderAppend,
        "msrt_strbuilder_append_int" => R::StrBuilderAppendInt,
        "msrt_string_concat" => R::StringConcat,
        "msrt_string_append" => R::StringAppend,
        "msrt_int_to_string" => R::IntToString,
        "msrt_list_sorted" => R::ListSorted,
        "msrt_list_new" => R::ListNew,
        "msrt_map_new" => R::MapNew,
        "msrt_bytes_values" => R::BytesValues,
        "msrt_string_eq" => R::StringEq,
        "msrt_cleanup_discard" | "msrt_cleanup_remove" => R::CleanupDiscard,
        "msrt_bytes_append" => R::BytesAppend,
        "msrt_string_split_view"
        | "msrt_map_keys_view"
        | "msrt_map_values_view"
        | "msrt_list_slice_view" => R::ViewResult,
        s if rt_flags(s).spawns => R::SpawnsTask,
        s if rt_flags(s).takes_self => R::TakesDying,
        _ => R::None,
    }
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
    let prefix = match m.types.kind(recv) {
        TyKind::Str => "string",
        TyKind::List(_) => "list",
        TyKind::Bytes => "bytes",
        TyKind::Int
        | TyKind::Int8
        | TyKind::Int16
        | TyKind::Int32
        | TyKind::UInt8
        | TyKind::UInt16
        | TyKind::UInt32 => "int",
        TyKind::Float | TyKind::Float32 => "float",
        TyKind::Obj(Native::Map, _) => "map",
        TyKind::Obj(Native::Set, _) => "set",
        _ => return None,
    };
    let sym = format!("msrt_{prefix}_{name}");
    if rt_sig(&sym).is_some() {
        return Some(sym);
    }
    // A set is a map without values: it shares the map entry points.
    let shared = format!("msrt_map_{name}");
    (prefix == "set")
        .then(|| rt_sig(&shared).map(|_| shared))
        .flatten()
}

/// The runtime symbol of `method` on an `extern type` of the standard library, named after the
/// type: `Regex.matches` is `msstd_regex_matches`.
pub(crate) fn typed_method_symbol(
    syms: ms_check::api::Names,
    recv: &ct::Ty,
    method: &str,
) -> Option<String> {
    let sym = recv.symbol()?;
    let external = sym.decl.as_ref().is_some_and(
        |d| matches!(&d.decl().kind, ms_check::api::ast::DeclKind::Record(r) if r.external),
    );
    if !external || recv.kind != ct::Kind::Native {
        return None;
    }
    let ty = syms.str(sym.name).to_lowercase();
    let symbol = format!("msstd_{ty}_{method}");
    rt_sig(&symbol).map(|_| symbol)
}

/// `STATUS_NONE`: end of stream or an absent optional.
const STATUS_NONE: i64 = 16;

/// What a handle a runtime call writes becomes in a `Result` payload.
#[derive(Clone, Copy)]
pub(crate) enum Wrap {
    /// An interface value over the handle, with the interface type.
    Iface(ms_mir::ir::VtableId, MTy),
    /// A type whose only field is the handle.
    Type(ms_mir::types::TypeId),
}

impl FnLower<'_> {
    /// The list type of a call result: the result itself, or the `ok` payload of a `Result`.
    fn result_list(&self, result: MTy) -> Option<MTy> {
        let t = &*self.b.m;
        match t.types.kind(result) {
            TyKind::List(_) => Some(result),
            TyKind::Alt(a) => t.alts[a.index()]
                .ok_case()
                .and_then(|k| t.alts[a.index()].cases[k].fields.first())
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
        // `Set[Int]` has fixed 16-byte slots (hash, key): `contains` and `add` skip descriptors.
        if *n == Native::Set && a.len() == 1 && a[0] == MTy::INT {
            return match sym {
                "msrt_map_contains" => Some("msrt_set_contains_w"),
                "msrt_set_add_copy" => Some("msrt_set_add_copy_w"),
                _ => None,
            };
        }
        if *n != Native::Map || a.len() != 2 {
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
            sig.params.len() - usize::from(sig.params.last().is_some_and(|p| p.ty == "ErrSlot"));
        let has_out = sig.params[..body].last().is_some_and(|p| p.name == "out");
        let end = body - usize::from(has_out);
        let mut vals: Vec<Value> = Vec::new();
        // Slots of borrowed owned values, taken back and dropped after the call.
        let mut cursor = 0;
        let mut i = 0;
        while i < end {
            let p = &sig.params[i];
            match p.name.as_str() {
                _ if p.ty == "ValueDesc" => {
                    // A generic value moved in or out of the runtime: the descriptor is that of the
                    // `value` argument, or of the result (`T?` gives that of `T`).
                    let by_value = decl
                        .iter()
                        .position(|p| self.syms.str(p.name) == "value")
                        .and_then(|k| inputs.get(k))
                        .and_then(|input| input.val)
                        .map(|v| self.ty_of(v.v));
                    let t = by_value.unwrap_or_else(|| match self.b.m.types.kind(result) {
                        TyKind::Opt(inner) => *inner,
                        _ => result,
                    });
                    vals.push(self.type_desc(t));
                }
                _ if p.ty == "ElemDesc" => {
                    // A function has no receiver: the descriptor is that of its list result
                    // (`flatten` takes lists of lists), or of its first list argument.
                    let first_list = inputs
                        .iter()
                        .filter_map(|input| input.val)
                        .map(|v| self.ty_of(v.v))
                        .find(|t| matches!(self.b.m.types.kind(*t), TyKind::List(_)));
                    let recv_ty = recv_ty
                        .or_else(|| self.result_list(result))
                        .or(first_list)
                        .ok_or_else(|| Error::new(format!("{sym}: descriptor without receiver")))?;
                    let e = match self.b.m.types.kind(recv_ty).clone() {
                        TyKind::List(e) => e,
                        TyKind::Obj(_, a) if !a.is_empty() => a[0],
                        _ => return Err(Error::new(format!("{sym}: no element type"))),
                    };
                    vals.push(self.type_desc(e));
                }
                _ if p.ty == "KeyDesc" || p.ty == "ValDesc" => {
                    let recv_ty = recv_ty
                        .ok_or_else(|| Error::new(format!("{sym}: descriptor without receiver")))?;
                    let TyKind::Obj(_, a) = self.b.m.types.kind(recv_ty).clone() else {
                        return Err(Error::new(format!("{sym}: not a map or set")));
                    };
                    let k = usize::from(p.ty == "ValDesc");
                    match a.get(k) {
                        Some(t) => vals.push(self.type_desc(*t)),
                        // A set is a map without a value descriptor.
                        None if k == 1 => vals.push(self.b.iconst(0)),
                        None => return Err(Error::new(format!("{sym}: no key type"))),
                    }
                }
                _ if p.ty == "HasRaw" && i + 1 < end && sig.params[i + 1].ty == "HasRaw" => {
                    // An optional type: its presence, then each field in turn.
                    let input = *inputs
                        .get(cursor)
                        .ok_or_else(|| Error::new(format!("{sym}: missing argument")))?;
                    cursor += 1;
                    i += 1 + self.flatten_optional_type(
                        input,
                        &sig.params[i + 1..end],
                        &mut vals,
                    )?;
                    continue;
                }
                _ if p.ty == "HasRaw" && i + 1 < end => {
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
                "env" => {
                    // The handler of a server: the closure the runtime calls per request.
                    let input = *inputs
                        .get(cursor)
                        .ok_or_else(|| Error::new(format!("{sym}: missing handler")))?;
                    cursor += 1;
                    let handler = input
                        .val
                        .ok_or_else(|| Error::new(format!("{sym}: missing handler")))?;
                    // The handler's type names the exchange interface: `fn(var HttpExchange) Unit!`.
                    let exchange = decl
                        .iter()
                        .find(|d| d.ty.kind == ms_check::api::types::Kind::Function)
                        .and_then(|d| d.ty.params.first().map(|q| q.ty.clone()))
                        .ok_or_else(|| Error::new(format!("{sym}: handler without an exchange")))?;
                    let exchange = self.mty(&exchange)?;
                    let env = self.handler_env(handler, exchange)?;
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
                    // A generic element slot takes the type whole, whatever its field is called.
                    let element = p.ty == "*const u8" || p.ty == "*mut u8";
                    if let Some(fields) = self.type_fields_named(x, &p.name).filter(|_| !element) {
                        // A type argument crosses as its fields.
                        let TyKind::Type(rid) = self.b.m.types.kind(self.ty_of(x.v)).clone() else {
                            unreachable!("type_fields_named found a type");
                        };
                        let tval = self.borrow(x);
                        for k in 0..fields {
                            let f = self.b.type_get(rid, k as u32, tval);
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
                    // A type the runtime reads as a `repr(C)` struct of the same leaves.
                    let wire = p.ty.starts_with("*const ") && p.ty.ends_with("Wire");
                    if p.ty == "*const u8"
                        || p.ty == "*mut u8"
                        || consumed_aggregate
                        || clock
                        || wire
                    {
                        // A generic element slot: pass the address of the value in memory.
                        // `*mut` hands the value over; `*const` is borrowed.
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
                            // Only read by the runtime: borrow the value itself.
                            let v = self.borrow(x);
                            self.b.emit(Op::Store, &[slot, v], Imm::None, None);
                        } else if self.needs_drop(t) {
                            let o = self.owned_arg(x);
                            self.b.emit(Op::Put, &[slot, o], Imm::None, None);
                        } else {
                            self.b.emit(Op::Store, &[slot, x.v], Imm::None, None);
                        }
                        vals.push(slot);
                    } else if hands_over(sym, i) {
                        // A function value the runtime keeps: handed over, dropped by the runtime.
                        let v = self.owned(x);
                        vals.push(v);
                    } else {
                        let v = self.borrow(x);
                        let v = match self.b.m.types.kind(self.ty_of(v)).clone() {
                            // A budget that may be absent crosses as `i64::MAX` when it is.
                            TyKind::Opt(t)
                                if p.ty == "i64" && (t == MTy::INT || self.is_duration(t)) =>
                            {
                                let has = self.b.opt_is_some(v);
                                let unlimited = self.b.iconst(i64::MAX);
                                let given = self.two_ways(
                                    has,
                                    MTy::INT,
                                    &mut |s| {
                                        let n = s.b.opt_get(v);
                                        Ok(Some(s.unduration(n)))
                                    },
                                    &mut |_| Ok(Some(unlimited)),
                                )?;
                                given.v
                            }
                            // A present optional string arrives as the plain string.
                            _ => self.unduration(v),
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

    /// The field count of a type argument whose first field is the runtime parameter `name`.
    fn type_fields_named(&self, x: Val, name: &str) -> Option<usize> {
        let TyKind::Type(rid) = self.b.m.types.kind(self.ty_of(x.v)) else {
            return None;
        };
        let fields = &self.b.m.type_defs[rid.index()].fields;
        (fields.first()?.0 == name).then_some(fields.len())
    }

    /// Pushes `has_type` and the `(has, value)` pairs of the optional fields of an optional
    /// type argument, reading fields only when the type is present. Returns the number of
    /// runtime parameters used after the presence flag.
    pub(crate) fn flatten_optional_type(
        &mut self,
        input: Input,
        params: &[RtParam],
        vals: &mut Vec<Value>,
    ) -> Result<usize, Error> {
        let x = input.val;
        let held = x.map(|x| self.ty_of(x.v));
        // The checker may already have converted the argument to an optional element.
        let wrapped = input.wrapped
            || held.is_some_and(|t| matches!(self.b.m.types.kind(t), TyKind::Type(_)));
        let type_ty = held.and_then(|t| match self.b.m.types.kind(t).clone() {
            TyKind::Opt(t) if !wrapped => Some(t),
            TyKind::Type(_) => Some(t),
            _ => None,
        });
        let fields = match type_ty.map(|t| self.b.m.types.kind(t).clone()) {
            Some(TyKind::Type(rid)) => self.b.m.type_defs[rid.index()].fields.clone(),
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
        // A type to read fields from: the argument itself, or the empty type when the
        // optional is none (the fields are then ignored by the runtime).
        let mut blank_val = None;
        let view = match (x, type_ty) {
            (Some(x), Some(rt)) => {
                let held = self.borrow(x);
                if wrapped {
                    Some(held)
                } else {
                    let TyKind::Type(rid) = self.b.m.types.kind(rt).clone() else {
                        unreachable!("fields come from a type");
                    };
                    let mut empty = Vec::new();
                    for (_, ft) in &fields {
                        empty.push(self.none_owned(*ft));
                    }
                    let blank = self.b.type_new(rid, &empty);
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
        while used + 1 < params.len() && params[used].ty == "HasRaw" {
            let payload = params[used + 1].ty.as_str();
            let zero = |s: &mut Self| match payload {
                "i64" => s.b.iconst(0),
                "f64" => s.b.fconst(0.0),
                _ => s.b.bconst(false),
            };
            let (fh, fv) = match (view, fields.get(k)) {
                (Some(tval), Some(_)) => {
                    let TyKind::Type(rid) = self
                        .b
                        .m
                        .types
                        .kind(type_ty.expect("view has a type"))
                        .clone()
                    else {
                        unreachable!("fields come from a type");
                    };
                    let f = self.b.type_get(rid, k as u32, tval);
                    let some = self.b.opt_get(f);
                    (self.b.opt_is_some(f), self.unduration(some))
                }
                _ => (self.b.bconst(false), zero(self)),
            };
            vals.push(fh);
            vals.push(fv);
            used += 2;
            k += 1;
        }
        // The runtime reads scalars only, so the empty type can go once they are out.
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
            return Ok((has, self.unduration(value)));
        }
        let value = if matches!(self.b.m.types.kind(ty), TyKind::Alt(_)) {
            self.b.alt_tag(v)
        } else {
            self.unduration(v)
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
        // A duration crosses as its nanosecond count.
        if self.is_duration(result) && self.ty_of(r.v) == MTy::INT {
            r.v = self.duration_of(r.v)?;
        }
        r.v = self.stamped(r.v)?;
        Ok(r)
    }

    /// The nanosecond count of a `Duration` operand, else the operand itself.
    pub(crate) fn unduration(&mut self, v: Value) -> Value {
        if self.is_duration(self.ty_of(v)) {
            return self.duration_nanos(v).expect("duration is a type");
        }
        v
    }

    /// Passes the slot a trailing `err` parameter writes the `Failed` text to.
    pub(crate) fn push_err_slot(&mut self, sig: &RtSig, vals: &mut Vec<Value>) {
        if sig.params.last().is_some_and(|p| p.ty == "ErrSlot") {
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
            sig.params.len() - usize::from(sig.params.last().is_some_and(|p| p.ty == "ErrSlot"));
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
                TyKind::Iface(_) => sig.returns_handle(),
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
                if self.ok_payload_is_optional_unit(result) {
                    // `Result[Unit?, E]`: `STATUS_NONE` is none, a zero status is some.
                    let take = &mut |s: &mut Self| Ok(s.b.unit());
                    return self.status_optional_result(sym, code, take, result);
                }
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
            if sig.returns_handle()
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
            // The runtime returns a sized integer as a word already in range.
            let sized = ret == MTy::INT && result != MTy::INT && self.b.m.types.is_int(result);
            if sized {
                let v = self.b.conv(out, result);
                return Ok(Val { v, own: false });
            }
            let owned = self.needs_drop(ret);
            return Ok(Val { v: out, own: owned });
        }
        if ret == MTy::UNIT {
            // The constructed value returns through the trailing out pointer.
            let out = self.call_runtime(sym, &vals, result)?;
            return Ok(Val { v: out, own: true });
        }
        // `InfoOut` is flat words that become a `FileInfo` type.
        let body =
            sig.params.len() - usize::from(sig.params.last().is_some_and(|p| p.ty == "ErrSlot"));
        if sig.params[..body]
            .last()
            .is_some_and(|p| p.ty == "*mut InfoOut")
        {
            return self.finish_stat(sym, sig, vals, result);
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
        // `Result[T?, E]`: the runtime writes a `T` and answers `STATUS_NONE` for none.
        let eof = match (self.b.m.types.kind(result), self.b.m.types.kind(payload)) {
            (TyKind::Alt(_), TyKind::Opt(inner)) => Some(*inner),
            _ => None,
        };
        // `Result[Interface, E]`: the runtime writes a handle, which the interface value wraps.
        let wrap = match (self.b.m.types.kind(result), self.b.m.types.kind(payload)) {
            (TyKind::Alt(_), TyKind::Iface(i)) => Some(*i),
            _ => None,
        };
        // `Result[Wrapper, E]` where `Wrapper` is a type around one runtime handle (a std type
        // such as `FileHandle { native: NativeFile }`): the runtime writes the handle and the
        // type is built around it.
        let kind = match (self.b.m.types.kind(result), self.b.m.types.kind(payload)) {
            (TyKind::Alt(_), TyKind::Type(r)) => {
                let fields = &self.b.m.type_defs[r.index()].fields;
                let one_handle = fields.len() == 1
                    && matches!(self.b.m.types.kind(fields[0].1), TyKind::Obj(..));
                one_handle.then_some((*r, fields[0].1))
            }
            _ => None,
        };
        let slot_ty = match (wrap, kind) {
            (Some(_), _) => crate::natiface::handle_ty(self.b.m),
            (None, Some((_, handle))) => handle,
            (None, None) => eof.unwrap_or(payload),
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
        let wrap = match (wrap, kind) {
            (Some(i), _) => {
                let hir = self.hir.clone();
                let vt = self.cx.handle_vtable_of(self.b.m, &hir, sym, i)?;
                Some(Wrap::Iface(vt, payload))
            }
            (None, Some((tval, _))) => Some(Wrap::Type(tval)),
            (None, None) => None,
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
        let mut vals = vals.to_vec();
        // A trailing `err` slot receives the text of a `Failed` status, read by `status_failure`;
        // a caller that marshalled its own arguments has already passed it.
        if let Some(sig) = rt_sig(sym)
            && vals.len() < sig.params.len()
        {
            self.err_slot = None;
            self.push_err_slot(&sig, &mut vals);
        }
        let raw = self.call_runtime(sym, &vals, MTy::INT)?;
        let mask = self.b.iconst(0xff);
        Ok(self.b.binop(Op::And, raw, mask))
    }

    /// The error case of `ea` that the status `code` names; the last listed case otherwise.
    /// A `Failed` status carries the text the native stored in the `err` slot.
    pub(crate) fn status_error(
        &mut self,
        ea: ms_mir::types::AltId,
        code: Value,
        cases: &[(i64, usize)],
    ) -> Result<Value, Error> {
        let (&(n, idx), rest) = cases
            .split_first()
            .ok_or_else(|| Error::new("no error case for a runtime status"))?;
        let build = |s: &mut Self| -> Result<Value, Error> {
            let carries_text = s.b.m.alts[ea.index()].cases[idx].fields.len() == 1;
            match s.err_slot {
                Some(slot) if carries_text => {
                    let text =
                        s.b.emit(Op::Take, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
                            .expect("take");
                    Ok(s.b.alt_new(ea, idx as u32, &[text]))
                }
                // A `Failed(message)` of a native without an `err` slot.
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
            s.status_error(ea, code, rest).map(Some)
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
            .ok_case()
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
            .error_case()
            .ok_or_else(|| Error::new("not a Result"))?;
        let et = self.b.m.alts[a.index()].cases[err].fields[0].1;
        if let TyKind::Type(er) = self.b.m.types.kind(et).clone() {
            let e = self.status_error_value(er, code, sym)?;
            return Ok(self.b.alt_new(a, err as u32, &[e]));
        }
        let et = self.b.m.alts[a.index()].cases[err].fields[0].1;
        let TyKind::Alt(ea) = self.b.m.types.kind(et).clone() else {
            return Err(Error::new("a runtime status needs an error alternative"));
        };
        // Every stdlib native returns an `Error` type; an alternative error type belongs to a
        // user `extern fn`, whose statuses number its cases 1 + declaration index.
        let cases: Vec<(i64, usize)> = (0..self.b.m.alts[ea.index()].cases.len())
            .map(|i| (i as i64 + 1, i))
            .collect();
        let e = self.status_error(ea, code, &cases)?;
        Ok(self.b.alt_new(a, err as u32, &[e]))
    }

    /// The `Error` value a nonzero runtime status `code` of `sym` stands for: the message names
    /// the module's domain and the failure, a `Failed` status carries the module's own text.
    pub(crate) fn status_error_value(
        &mut self,
        er: ms_mir::types::TypeId,
        code: Value,
        sym: &str,
    ) -> Result<Value, Error> {
        if rt_sig(sym).is_none() {
            return Err(Error::new(format!(
                "{sym}: no runtime function names this status"
            )));
        }
        let table = status_table(sym);
        let domain = domain_of(sym);
        self.status_chain(er, code, &table, &domain)
    }

    fn status_chain(
        &mut self,
        er: ms_mir::types::TypeId,
        code: Value,
        table: &[(i64, &'static str, &'static str)],
        domain: &str,
    ) -> Result<Value, Error> {
        let (&(n, kind, words), rest) = table
            .split_first()
            .ok_or_else(|| Error::new("no error kind for a runtime status"))?;
        let build = |s: &mut Self| -> Result<Value, Error> {
            let text = if words == "-" {
                match s.err_slot {
                    Some(slot) => {
                        s.b.emit(Op::Take, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
                            .expect("take")
                    }
                    None => {
                        let l = s.lit(&format!("{domain}: failed")).v;
                        s.owned(Val { v: l, own: false })
                    }
                }
            } else {
                let fallback = format!("{domain}: {words}");
                let literal = |s: &mut Self| {
                    let l = s.lit(&fallback).v;
                    s.owned(Val { v: l, own: false })
                };
                match s.err_slot {
                    // A native with an `err` slot may explain the failure (a position, a path):
                    // its non-empty text follows the status words.
                    Some(slot) => {
                        let said =
                            s.b.emit(Op::Take, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR))
                                .expect("take");
                        let len = s.b.str_len(said);
                        let zero = s.b.iconst(0);
                        let has = s.b.icmp(Cc::Gt, len, zero);
                        s.two_ways(
                            has,
                            MTy::STR,
                            &mut |s| {
                                let head = s.b.str_lit(&format!("{fallback}: "));
                                let both =
                                    s.call_runtime("msrt_string_concat", &[head, said], MTy::STR)?;
                                s.drop_value(said);
                                Ok(Some(both))
                            },
                            &mut |s| {
                                s.drop_value(said);
                                Ok(Some(literal(s)))
                            },
                        )?
                        .v
                    }
                    None => literal(s),
                }
            };
            s.error_type(er, kind, text, None)
        };
        if rest.is_empty() {
            return build(self);
        }
        let k = self.b.iconst(n);
        let hit = self.b.icmp(Cc::Eq, code, k);
        let ty = self.b.m.types.named(er);
        let r = self.two_ways(hit, ty, &mut |s| build(s).map(Some), &mut |s| {
            s.status_chain(er, code, rest, domain).map(Some)
        })?;
        Ok(r.v)
    }

    /// An `Error` type: the owned `message`, the error code `kind` (such as `ENOENT`), and the
    /// details `{"site": site}` when a failed test expectation passes its source `site`.
    pub(crate) fn error_type(
        &mut self,
        er: ms_mir::types::TypeId,
        kind: &str,
        message: Value,
        site: Option<Value>,
    ) -> Result<Value, Error> {
        let fields = self.b.m.type_defs[er.index()].fields.clone();
        let code = self.b.str_lit(kind);
        let code = self.owned(Val {
            v: code,
            own: false,
        });
        let kind_value = self.b.opt_some(code);
        let mut details = self.map_new(fields[2].1)?;
        if let Some(site) = site {
            let key = self.b.str_lit("site");
            // The map takes owned strings; literals are borrowed.
            let (key, site) = (self.owned_copy(key), self.owned_copy(site));
            details = self.map_insert(details, key, site)?;
        }
        Ok(self.b.type_new(er, &[message, kind_value, details]))
    }

    /// An clone of the borrowed string `v`.
    fn owned_copy(&mut self, v: Value) -> Value {
        self.b
            .emit(Op::Clone, &[v], Imm::None, Some(MTy::STR))
            .expect("copy")
    }

    /// Whether the `ok` payload of `result` is `Unit?`.
    fn ok_payload_is_optional_unit(&self, result: MTy) -> bool {
        let TyKind::Alt(a) = self.b.m.types.kind(result) else {
            return false;
        };
        let Ok(ok) = self.ok_case_index(*a) else {
            return false;
        };
        let payload = self.b.m.alts[a.index()].cases[ok].fields[0].1;
        matches!(self.b.m.types.kind(payload), TyKind::Opt(t) if *t == MTy::UNIT)
    }

    /// `ok(value)` when the status is zero, else the error case the status names.
    pub(crate) fn status_result(
        &mut self,
        sym: &str,
        code: Value,
        out: Option<(Value, MTy)>,
        wrap: Option<Wrap>,
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
                    Some(Wrap::Iface(vt, it)) => {
                        s.b.emit(Op::IfaceNew, &[payload], Imm::Vtable(vt), Some(it))
                            .expect("iface")
                    }
                    Some(Wrap::Type(tval)) => s.b.type_new(tval, &[payload]),
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

include!(concat!(env!("OUT_DIR"), "/status_rows.rs"));

/// The error code and message words of each runtime status of `sym`'s module, as
/// `(status, kind, words)`. The rows are declared in the standard library next to `Error.kind`
/// (`stdlib/core.ms`); a module's own wording for a status is declared in the file that holds
/// `sym` (see `build.rs`). Words `-` mean the native's own text is the message.
pub(crate) fn status_table(sym: &str) -> Vec<(i64, &'static str, &'static str)> {
    STATUS_ROWS
        .iter()
        .map(|&(n, kind, words)| {
            let own = STATUS_WORDS
                .binary_search_by(|&(s, status, _)| (s, status).cmp(&(sym, n)))
                .map(|at| STATUS_WORDS[at].2);
            (n, kind, own.unwrap_or(words))
        })
        .collect()
}

/// How the failures of `sym` name their domain, as its runtime source declares.
fn domain_of(sym: &str) -> String {
    rt_flags(sym).domain.unwrap_or("runtime").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every `// ms: op=<mnemonic>` names a MIR instruction.
    #[test]
    fn declared_ops_are_instructions() {
        for (sym, .., op, _) in SYMBOLS {
            if !op.is_empty() {
                assert!(
                    Op::from_name(op).is_some(),
                    "{sym}: unknown instruction {op}"
                );
            }
        }
    }
}
