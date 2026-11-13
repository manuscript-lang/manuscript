//! Standard-library natives: runtime calls and inline sequences.

use crate::Error;
use crate::func::{FnLower, Val};
use ms_check::api::ast::*;
use ms_check::api::hir::{CallView, Resolution};
use ms_check::api::syntax::DefaultForm;
use ms_check::api::types as ct;
use ms_check::api::types::Builtin;
use ms_mir::ir::{Imm, Mode, Op, Param, Value};
use ms_mir::types::Native;
use ms_mir::types::{Ty as MTy, TyKind};

mod defaults;
mod list;
mod method;
mod mutate;
mod optional;

/// String operations `fn(String) -> String` and their runtime symbols.
/// Methods of format enums: native, runtime symbol, the runtime's format parameter, and whether
/// the runtime wants the case index (else the lowercase case name).
const FORMAT_METHODS: &[(&str, &str, &str, bool)] =
    &[("normalize", "msrt_string_normalize_kind", "kind", true)];

const STRING_TO_STRING: &[(&str, &str)] = &[
    ("reverse", "msrt_string_reverse"),
    ("lower", "msrt_string_lower"),
    ("upper", "msrt_string_upper"),
    ("trim", "msrt_string_trim"),
    ("trim_start", "msrt_string_trim_start"),
    ("trim_end", "msrt_string_trim_end"),
];

/// A string method that maps its borrowed operands straight to a runtime function.
const PLAIN_STRING: &[(&str, &str, MTy)] = &[
    ("length", "msrt_string_length", MTy::INT),
    ("scalar_length", "msrt_string_scalar_length", MTy::INT),
    ("byte_length", "msrt_string_byte_length", MTy::INT),
    ("is_empty", "msrt_string_is_empty", MTy::BOOL),
    ("contains", "msrt_string_contains", MTy::BOOL),
    ("starts_with", "msrt_string_starts_with", MTy::BOOL),
    ("ends_with", "msrt_string_ends_with", MTy::BOOL),
    ("count", "msrt_string_count", MTy::INT),
    ("concat", "msrt_string_concat", MTy::STR),
    ("compare", "msrt_string_compare", MTy::INT),
];

/// Loop body: `(index, element)` to an optional exit condition.
type ElementBody<'b, S> = dyn FnMut(&mut S, Value, Value) -> Result<Option<Value>, Error> + 'b;

/// A branch body producing an owned value, or `None` when it diverges.
type BranchBody<'b, S> = dyn FnMut(&mut S) -> Result<Option<Value>, Error> + 'b;

/// Whether `name` is an `Optional` method lowered inline.
fn opt_method(name: &str) -> bool {
    matches!(
        name,
        "is_some"
            | "is_none"
            | "get"
            | "get_or_else"
            | "map"
            | "and_then"
            | "or_else"
            | "ok_or"
            | "ok_or_else"
    )
}

/// List methods that take a function and run it over the elements.
fn is_higher_order(name: &str) -> bool {
    matches!(
        name,
        "map"
            | "filter"
            | "flat_map"
            | "partition"
            | "group_by"
            | "count"
            | "any"
            | "all"
            | "for_each"
            | "find"
            | "find_index"
            | "find_last_index"
    )
}

/// An evaluated argument of a native call.
#[derive(Clone, Copy)]
pub(crate) struct NArg {
    pub name: ms_check::api::types::Name,
    pub val: Val,
    pub wrapped: bool,
    /// A function that only reads the parameters of the `var` function type it fills, passed as
    /// written, without the adapter: the callee hands it values, not addresses.
    pub reader: bool,
}

impl<'a> FnLower<'a> {
    pub fn native_function(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        native: ct::Native,
        params: &[ct::Param],
        sym: &ct::SymRef,
    ) -> Result<Val, Error> {
        let native = match native {
            ct::Native::Builtin(identity) => self.syms.str(identity),
            ct::Native::Extern { symbol, bundled } => {
                return self.runtime_function(e, view, self.syms.str(symbol), bundled, params, sym);
            }
            ct::Native::Source | ct::Native::Contract => {
                return Err(Error::new("a function with a body is not native"));
            }
        };
        self.builtin_function(e, view, native, params, sym)
    }

    /// A call of an `extern fn`: a bundled one is a runtime function whose convention the runtime
    /// table declares; a user one calls its shim.
    fn runtime_function(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        symbol: &str,
        bundled: bool,
        params: &[ct::Param],
        sym: &ct::SymRef,
    ) -> Result<Val, Error> {
        if !bundled {
            return self.extern_call(e, view, symbol, sym);
        }
        // A runtime function that is one instruction on its arguments is emitted as that instruction.
        if let Some(op) = crate::rtcall::rt_flags(symbol).op {
            let args = self.native_args(view)?;
            if self.dead {
                return Ok(self.dummy(MTy::UNIT));
            }
            let result = self.emty(e)?;
            self.at(e.pos);
            return self.single_op(symbol, op, &args, result);
        }
        // A symbol that is lowered by hand keeps its native identity.
        if let Some(hand) = crate::stdnative::by_symbol(symbol) {
            return self.builtin_function(e, view, hand.identity, params, sym);
        }
        // A bundled extern is a runtime symbol; its convention comes from the runtime's declaration.
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let result = self.emty(e)?;
        self.at(e.pos);
        self.rt_function(symbol, params, &args, result)
    }

    /// A call of a bodiless standard function the compiler lowers, by its `module/name` identity.
    fn builtin_function(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        native: &str,
        params: &[ct::Param],
        sym: &ct::SymRef,
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
            "core/panic" => {
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
                    fresh: false,
                    role: ms_mir::ir::ExternRole::None,
                    leaf: crate::rtcall::rt_flags("msrt_fault_string").leaf,
                    reads: crate::rtcall::rt_flags("msrt_fault_string").reads,
                });
                self.at(e.pos);
                self.b.call_rt(ext, &[m]);
                Ok(self.dummy(MTy::UNIT))
            }
            "json/parse" | "json/stringify" => {
                let mut args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let func = sym.decl.as_ref().and_then(|d| d.func());
                self.fill_native_defaults(sym.module, func, params, &mut args)?;
                self.at(e.pos);
                // The runtime answers with the declared error type; the use may expect a wider one.
                let mut subst = ct::Subst::new();
                if let (Some(v), Some(a)) = (sym.variables().first(), self.ety(e).args.first()) {
                    subst.insert(v.id, a.clone());
                }
                let declared = ct::sub(&sym.ty(self.syms).result_ty(), &subst);
                let have = self.mty(&declared)?;
                let r = if native == "json/parse" {
                    let t = self
                        .ety(e)
                        .args
                        .first()
                        .cloned()
                        .ok_or_else(|| Error::new("parse without a result type"))?;
                    self.json_parse(&t, have, &args)?
                } else {
                    let value = view
                        .arguments
                        .iter()
                        .find(|a| self.syms.str(a.slot.name) == "value")
                        .ok_or_else(|| Error::new("stringify without a value"))?;
                    let t = self.ety(value.expr);
                    self.json_stringify(t, have, &args)?
                };
                let want = self.emty(e)?;
                self.fit_ty(r, &declared, want)
            }
            "collections/map_from_entries" => {
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let result = self.emty(e)?;
                self.at(e.pos);
                self.native_call(native, params, &args, result)
            }
            "embed/bytes" => {
                // The argument is the Base64 text of the file, decoded here so the program holds
                // the raw bytes in read-only data and a read decodes nothing.
                let text = view
                    .arguments
                    .first()
                    .and_then(|a| match &a.expr.kind {
                        ExprKind::Text(parts) => match parts.as_slice() {
                            [] => Some(""),
                            [ms_check::api::ast::TextPart::Lit(t)] => Some(&**t),
                            _ => None,
                        },
                        _ => None,
                    })
                    .ok_or_else(|| {
                        Error::new("the argument of msstd_embed_bytes is a string literal")
                    })?;
                let data = decode_base64(text)
                    .ok_or_else(|| Error::new("the argument of msstd_embed_bytes is not Base64"))?;
                self.at(e.pos);
                let v = self.b.bytes_lit(data);
                Ok(Val { v, own: false })
            }
            other if crate::stdnative::handle_of(other).is_some() => {
                let handle = crate::stdnative::handle_of(other).expect("checked");
                let (ity, want) = (self.ety(e), self.emty(e)?);
                self.handle_interface(&ity, want, handle.module, handle.make, handle.constant)
            }
            other if other.starts_with("test/") => {
                self.testing_native(e, view, &other["test/".len()..])
            }
            other => {
                if !self.has_native_call(other) {
                    return Err(Error::new(format!("unsupported native function {other}")));
                }
                let mut args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let func = sym.decl.as_ref().and_then(|d| d.func());
                self.fill_native_defaults(sym.module, func, params, &mut args)?;
                let result = self.emty(e)?;
                self.at(e.pos);
                self.native_call(other, params, &args, result)
            }
        }
    }

    /// Whether `native_call` lowers the native function `native`.
    fn has_native_call(&self, native: &str) -> bool {
        crate::rtcall::function_symbol(native).is_some()
    }

    /// A native function applied to evaluated arguments (borrowed by the callee).
    pub(crate) fn native_call(
        &mut self,
        native: &str,
        params: &[ct::Param],
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        if native == "collections/map_from_entries" {
            return self.map_from_entries(args[0].val, result);
        }
        let sym = crate::rtcall::function_symbol(native)
            .ok_or_else(|| Error::new(format!("unsupported native function {native}")))?;
        self.rt_function(&sym, params, args, result)
    }

    /// The runtime function `symbol` declared as the MIR instruction `op` on its arguments.
    pub(crate) fn single_op(
        &mut self,
        symbol: &str,
        op: &str,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let op = Op::from_name(op)
            .ok_or_else(|| Error::new(format!("{symbol}: unknown instruction {op}")))?;
        let vals: Vec<Value> = args.iter().map(|a| self.borrow(a.val)).collect();
        let v = self
            .b
            .emit(op, &vals, Imm::None, Some(result))
            .ok_or_else(|| Error::new(format!("{symbol}: instruction without a result")))?;
        Ok(Val { v, own: false })
    }

    /// `value.hash()` of any hashable value: the runtime hashes the value in memory as map keys are.
    pub(crate) fn derived_hash(&mut self, recv: Val) -> Result<Val, Error> {
        if self.ty_of(recv.v) == MTy::STR {
            let s = self.borrow(recv);
            let h = self.call_runtime("msrt_string_hash", &[s], MTy::INT)?;
            return Ok(Val { v: h, own: false });
        }
        self.structural_hash(recv)
    }

    fn structural_hash(&mut self, recv: Val) -> Result<Val, Error> {
        use ms_mir::ir::{Imm, Op};
        let x = self.borrow(recv);
        let t = self.ty_of(x);
        let desc = self.type_desc(t);
        let slot = self
            .b
            .emit(Op::Slot, &[], Imm::Ty(t), Some(MTy::PTR))
            .expect("slot");
        self.b.emit(Op::Store, &[slot, x], Imm::None, None);
        let h = self.call_runtime("msrt_slot_hash", &[desc, slot], MTy::INT)?;
        Ok(Val { v: h, own: false })
    }

    /// A method of a format enum (`text.normalize(form)`): the runtime takes the format as a
    /// parameter after the first declared one, spelled as the lowercase case name or as its index.
    /// `map_from_entries(entries)`: later entries replace earlier values for a repeated key.
    fn map_from_entries(&mut self, entries: Val, map: MTy) -> Result<Val, Error> {
        let list = self.borrow(entries);
        let lt = self.ty_of(list);
        let TyKind::List(entry) = self.b.m.types.kind(lt).clone() else {
            return Err(Error::new("map_from_entries takes a list"));
        };
        let TyKind::Type(rid) = self.b.m.types.kind(entry).clone() else {
            return Err(Error::new("map_from_entries takes entry types"));
        };
        let lvar = self.fresh_var(lt);
        let held = self.clone_value(list);
        self.b.def_var(lvar, held);
        let acc = self.fresh_var(map);
        let fresh = self.map_new(map)?;
        self.b.def_var(acc, fresh);
        self.each_element(lvar, &mut |s, _, item| {
            let (k, v) = (s.b.type_get(rid, 0, item), s.b.type_get(rid, 1, item));
            let k = s.clone_value(k);
            let v = s.clone_value(v);
            let old = s.b.use_var(acc);
            let new = s.map_insert(old, k, v)?;
            s.b.def_var(acc, new);
            Ok(None)
        })?;
        self.release_source(lvar, true);
        let out = self.b.use_var(acc);
        Ok(Val { v: out, own: true })
    }

    /// The runtime's format argument: the case index, or the lowercase case name.
    fn format_argument(
        &mut self,
        m: &ct::MethodRef,
        recv: Val,
        as_text: bool,
    ) -> Result<Val, Error> {
        let tag_src = self.borrow(recv);
        let tag = self.b.alt_tag(tag_src);
        if as_text {
            return Ok(Val { v: tag, own: false });
        }
        let names: Vec<String> = ct::cases(&m.receiver)
            .iter()
            .map(|c| self.syms.str(c.name).to_lowercase())
            .collect();
        self.case_name(&names, tag, 0)
    }

    /// The owned name of case `tag`, counting from `names[from]`; the last name is the fallback.
    fn case_name(&mut self, names: &[String], tag: Value, from: usize) -> Result<Val, Error> {
        let text = |s: &mut Self, name: &str| {
            let lit = s.lit(name).v;
            Some(s.owned(Val { v: lit, own: false }))
        };
        if from + 1 >= names.len() {
            let name = names.last().map_or("", String::as_str);
            return Ok(Val {
                v: text(self, name).expect("copy"),
                own: true,
            });
        }
        let idx = self.b.iconst(from as i64);
        let hit = self.b.icmp(ms_mir::ir::Cc::Eq, tag, idx);
        let name = names[from].clone();
        self.two_ways(hit, MTy::STR, &mut |s| Ok(text(s, &name)), &mut |s| {
            s.case_name(names, tag, from + 1).map(|v| Some(v.v))
        })
    }

    fn format_method(
        &mut self,
        result: MTy,
        m: &ct::MethodRef,
        recv: Val,
        mut args: Vec<NArg>,
        (sym, param, as_text): (&str, &str, bool),
    ) -> Result<Val, Error> {
        let val = self.format_argument(m, recv, as_text)?;
        let name = self.syms.intern(param);
        args.push(NArg {
            name,
            val,
            wrapped: false,
            reader: false,
        });
        let first =
            m.ty.params
                .first()
                .ok_or_else(|| Error::new("format method without arguments"))?
                .clone();
        let mut decl = vec![first.clone()];
        decl.push(ct::Param::new(name, first.ty));
        decl.extend(m.ty.params.iter().skip(1).cloned());
        self.rt_function(sym, &decl, &args, result)
    }

    /// Whether an argument of the call assigns the variable at the root of the receiver place.
    fn argument_reassigns(&self, recv_expr: &Expr, view: &CallView<'_>) -> bool {
        if !self.is_place(recv_expr) {
            return false;
        }
        let Some(uid) = crate::mutation::place_root(self.syms, &self.hir, recv_expr) else {
            return false;
        };
        view.arguments.iter().any(|a| {
            crate::mutation::mutated_locals(
                self.syms,
                &self.hir,
                ms_check::api::hir::Body::Expr(a.expr),
                &self.cx.callables,
                &self.cx.mutated,
            )
            .contains(&uid)
        })
    }

    /// A sized integer or `Float32` as `Int` or `Float`; other values unchanged.
    fn widen_numeric(&mut self, v: Val) -> Val {
        let t = self.ty_of(v.v);
        let to = if self.b.m.types.is_int(t) {
            MTy::INT
        } else if self.b.m.types.is_float(t) {
            MTy::FLOAT
        } else {
            return v;
        };
        if t == to {
            return v;
        }
        Val {
            v: self.b.conv(v.v, to),
            own: false,
        }
    }

    /// The `UInt64` operations whose runtime function treats the word as unsigned.
    fn uint64_method(
        &mut self,
        native: &str,
        result: MTy,
        recv: Val,
        args: &[NArg],
    ) -> Result<Option<Val>, Error> {
        let name = native.rsplit('/').next().unwrap_or(native);
        let v = self.borrow(recv);
        let out = match name {
            "to_string_radix" => {
                let radix = self.borrow(args[0].val);
                self.call_runtime("msrt_uint_to_string_radix", &[v, radix], MTy::STR)?
            }
            "to_string" if args.is_empty() => {
                self.call_runtime("msrt_uint_to_string", &[v], MTy::STR)?
            }
            "compare" => {
                let other = self.borrow(args[0].val);
                self.call_runtime("msrt_uint_compare", &[v, other], MTy::INT)?
            }
            "to_decimal" => self.call_runtime("msstd_decimal_from_uint", &[v], result)?,
            _ => return Ok(None),
        };
        Ok(Some(Val {
            v: out,
            own: name != "compare",
        }))
    }

    /// `to_int8()` ... `to_float64()`: widening is exact, narrowing an integer yields an
    /// optional, and a float conversion rounds to the target.
    fn numeric_conversion(&mut self, result: MTy, recv: Val) -> Result<Val, Error> {
        let x = self.borrow(recv);
        let from = self.ty_of(x);
        let types = &self.b.m.types;
        let v = if let Some(inner) = self.b.m.opt_inner(result) {
            self.b.inarrow_opt(x, inner)
        } else if types.is_float(result) {
            let float = if from == MTy::UINT64 {
                let sym = if result == MTy::FLOAT32 {
                    "msrt_uint_to_float32"
                } else {
                    "msrt_uint_to_float"
                };
                self.call_runtime(sym, &[x], MTy::FLOAT)?
            } else if types.is_int(from) {
                self.b.i2f(x, result)
            } else {
                x
            };
            if self.ty_of(float) == result {
                float
            } else {
                self.b.conv(float, result)
            }
        } else {
            self.b.conv(x, result)
        };
        Ok(Val { v, own: false })
    }
}

impl FnLower<'_> {
    /// What an in-place walk of the receiver yields for method `m`, when it is one a `for` can
    /// walk without building a list.
    fn walk_kind(&self, m: &ct::MethodRef, recv: Value) -> Option<crate::stmt::Walk> {
        use crate::stmt::Walk;
        let TyKind::Obj(n, _) = self.b.m.types.kind(self.ty_of(recv)) else {
            return None;
        };
        match (n, self.syms.str(m.name()?)) {
            (Native::Map, "entries") => Some(Walk::Entries),
            (Native::Map, "values") => Some(Walk::Values),
            (Native::Map, "keys") | (Native::Set, "values") => Some(Walk::Keys),
            _ => None,
        }
    }

    /// The runtime entry that lists a map's keys (or values) as borrowed views, when `m` is that
    /// method on a map that stays unchanged for the whole call.
    fn keys_view_symbol(
        &self,
        m: &ct::MethodRef,
        recv_expr: &Expr,
        recv: Value,
    ) -> Option<&'static str> {
        if !self.stable_place(recv_expr) {
            return None;
        }
        let is_map = matches!(
            self.b.m.types.kind(self.ty_of(recv)),
            TyKind::Obj(Native::Map, _)
        );
        match self.syms.str(m.name()?) {
            "keys" if is_map => Some("msrt_map_keys_view"),
            "values" if is_map => Some("msrt_map_values_view"),
            _ => None,
        }
    }
}

/// The bytes of standard Base64 text with `=` padding, or `None` when the text is not Base64.
fn decode_base64(text: &str) -> Option<Vec<u8>> {
    let bytes = text.as_bytes();
    if !bytes.len().is_multiple_of(4) {
        return None;
    }
    let sextet = |c: u8| -> Option<u32> {
        match c {
            b'A'..=b'Z' => Some(u32::from(c - b'A')),
            b'a'..=b'z' => Some(u32::from(c - b'a') + 26),
            b'0'..=b'9' => Some(u32::from(c - b'0') + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    };
    let mut out = Vec::with_capacity(bytes.len() / 4 * 3);
    for (i, chunk) in bytes.chunks(4).enumerate() {
        let last = (i + 1) * 4 == bytes.len();
        let pad = chunk.iter().rev().take_while(|c| **c == b'=').count();
        if pad > 2 || (pad > 0 && !last) {
            return None;
        }
        let mut word = 0u32;
        for &c in &chunk[..4 - pad] {
            word = word << 6 | sextet(c)?;
        }
        word <<= 6 * pad as u32;
        out.extend_from_slice(&word.to_be_bytes()[1..4 - pad]);
    }
    Some(out)
}
