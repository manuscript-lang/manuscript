//! Standard-library natives: runtime calls and inline sequences.

use crate::Error;
use crate::func::{FnLower, Val};
use crate::text::runtime_fn;
use ms_check::hir::{CallView, Resolution};
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Linkage, Mode, Param, Value};
use ms_mir::types::{Ty as MTy, TyKind};
use ms_syntax::ast::*;

/// String operations `fn(String) -> String` and their runtime symbols.
/// Methods of format enums: native, runtime symbol, the runtime's format parameter, and whether
/// the runtime wants the case index (else the lowercase case name).
const FORMAT_METHODS: &[(&str, &str, &str, bool)] = &[(
    "string/form_normalize",
    "msrt_string_normalize_kind",
    "kind",
    true,
)];

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
    pub name: ms_check::types::Name,
    pub val: Val,
    pub wrapped: bool,
}

/// The native identity of `@std/data/json.ms`'s typed calls, which its source module declares as externs.
pub(crate) fn json_native(native: &str) -> &str {
    match native {
        "extern:msrt_json_parse" => "json/parse",
        "extern:msrt_json_stringify" => "json/stringify",
        other => other,
    }
}

impl<'a> FnLower<'a> {
    pub fn native_function(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        native: &str,
        params: &[ct::Param],
        sym: &ct::SymRef,
    ) -> Result<Val, Error> {
        let native = json_native(native);
        if let Some(symbol) = native.strip_prefix("extern:") {
            if !sym.module.as_str().starts_with("@std/") {
                return self.extern_call(e, view, symbol, sym);
            }
            // The runtime keeps the first of equal elements and receives the element descriptor like a method call.
            if symbol == "msrt_list_distinct" {
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let result = self.emty(e)?;
                return self.rt_method(symbol, args[0].val, &params[1..], &args[1..], result);
            }
            // Float rounding and square root are single instructions.
            if let Some(op) = match symbol {
                "msstd_math_sqrt" => Some(ms_mir::ir::Op::FSqrt),
                "msstd_math_floor" => Some(ms_mir::ir::Op::FFloor),
                "msstd_math_ceil" => Some(ms_mir::ir::Op::FCeil),
                "msstd_math_truncate" => Some(ms_mir::ir::Op::FTrunc),
                _ => None,
            } {
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let x = self.borrow(args[0].val);
                self.at(e.pos);
                let v = self
                    .b
                    .emit(op, &[x], ms_mir::ir::Imm::None, Some(MTy::FLOAT))
                    .expect("float op");
                return Ok(Val { v, own: false });
            }
            // The `@std/math` bit operations declare their natives as externs; on `Int` each is one instruction.
            if let Some(name) = symbol.strip_prefix("msrt_bits_").filter(|n| {
                matches!(
                    *n,
                    "bit_and"
                        | "bit_or"
                        | "bit_xor"
                        | "bit_not"
                        | "shift_left"
                        | "shift_right"
                        | "shift_right_unsigned"
                        | "wrapping_add"
                        | "wrapping_subtract"
                        | "wrapping_multiply"
                )
            }) {
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                self.at(e.pos);
                return self.bit_operation(name, &args);
            }
            // Codec streams are built by the compiler: the format name, the input, and the limit.
            if matches!(
                symbol,
                "msstd_archive_compress_stream" | "msstd_archive_decompress_stream"
            ) {
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let result = self.emty(e)?;
                self.at(e.pos);
                let decode = symbol == "msstd_archive_decompress_stream";
                return self.codec_stream(args[0].val, &args[1..], decode, result);
            }
            // A symbol that is lowered by hand keeps its native identity.
            if let Some(hand) = crate::stdnative::by_symbol(symbol) {
                return self.native_function(e, view, hand.identity, params, sym);
            }
            // A bundled extern is a runtime symbol; its convention comes from the runtime's declaration.
            let args = self.native_args(view)?;
            if self.dead {
                return Ok(self.dummy(MTy::UNIT));
            }
            let result = self.emty(e)?;
            self.at(e.pos);
            // The host-rule path functions share the interface's entry points; a leading `windows` flag the
            // declaration does not spell selects the host's rules.
            if crate::rtcall::rt_sig(symbol)
                .is_some_and(|sig| sig.params.first().is_some_and(|p| p.name == "windows"))
                && params.first().is_none_or(|p| p.name.as_str() != "windows")
            {
                let name = ct::n("windows");
                let v = self.b.bconst(cfg!(windows));
                let mut args = args;
                args.insert(
                    0,
                    NArg {
                        name,
                        val: Val { v, own: false },
                        wrapped: false,
                    },
                );
                let mut decl = params.to_vec();
                decl.insert(
                    0,
                    ct::Param {
                        name,
                        ty: ct::bool_(),
                    },
                );
                return self.rt_function(symbol, &decl, &args, result);
            }
            return self.rt_function(symbol, params, &args, result);
        }
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
                let declared = ct::sub(&sym.ty().result_ty(), &subst);
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
                        .find(|a| a.slot.name.as_str() == "value")
                        .ok_or_else(|| Error::new("stringify without a value"))?;
                    let t = self.ety(value.expr);
                    self.json_stringify(t, have, &args)?
                };
                let want = self.emty(e)?;
                self.fit_ty(r, &declared, want)
            }
            "random/draw_int"
            | "random/draw_uuid"
            | "random/draw_float"
            | "random/draw_shuffle"
            | "random/draw_choice" => self.random_native(e, view, native),
            "html/parse" => {
                let mut args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let func = sym.decl.as_ref().and_then(|d| d.func());
                self.fill_native_defaults(sym.module, func, params, &mut args)?;
                self.at(e.pos);
                let rty = self.emty(e)?;
                let node = self
                    .ety(e)
                    .args
                    .first()
                    .cloned()
                    .ok_or_else(|| Error::new("parse without a node type"))?;
                self.html_parse(&node, rty, &args)
            }
            "shared/share" => {
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let result = self.emty(e)?;
                self.at(e.pos);
                let held = self.ety(e).args.first().cloned();
                let shared = self.native_call(native, params, &args, result)?;
                if let Some(held) = held {
                    self.register_shared_close(&held, result)?;
                }
                Ok(shared)
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
            "io/stdout" | "io/stderr" => {
                let it = self.emty(e)?;
                self.std_stream(it, native == "io/stderr")
            }
            "time/clock" | "time/wall_clock" => {
                let it = self.emty(e)?;
                self.time_clock(it, native == "time/wall_clock")
            }
            "io/read_line" => self.read_line_native(e, view, params),
            "math/min" => self.math_extreme(view, false),
            "math/max" => self.math_extreme(view, true),
            "io/read_all" => self.stream_native(e, view, crate::streamloop::Loop::ReadAll),
            "io/copy" => self.stream_native(e, view, crate::streamloop::Loop::Copy),
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
                if other.starts_with("crypto/rsa_") {
                    // The C ABI produces CryptoError even when the source expects Error.
                    let declared = sym.ty().result_ty();
                    let have = self.mty(&declared)?;
                    self.at(e.pos);
                    let r = self.native_call(other, params, &args, have)?;
                    let want = self.emty(e)?;
                    return self.fit_ty(r, &declared, want);
                }
                let result = self.emty(e)?;
                self.at(e.pos);
                self.native_call(other, params, &args, result)
            }
        }
    }

    /// Whether `native_call` lowers the native function `native`.
    fn has_native_call(&self, native: &str) -> bool {
        matches!(
            native,
            "math/min"
                | "math/max"
                | "shared/share"
                | "core/category"
                | "math/bit_and"
                | "math/bit_or"
                | "math/bit_xor"
                | "math/bit_not"
                | "math/shift_left"
                | "math/shift_right"
                | "math/shift_right_unsigned"
                | "math/wrapping_add"
                | "math/wrapping_subtract"
                | "math/wrapping_multiply"
        ) || crate::rtcall::function_symbol(native).is_some()
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
        if let Some(name) = native.strip_prefix("math/").filter(|n| {
            matches!(
                *n,
                "bit_and"
                    | "bit_or"
                    | "bit_xor"
                    | "bit_not"
                    | "shift_left"
                    | "shift_right"
                    | "shift_right_unsigned"
                    | "wrapping_add"
                    | "wrapping_subtract"
                    | "wrapping_multiply"
            )
        }) {
            return self.bit_operation(name, args);
        }
        if native == "core/category" {
            let cause = self.borrow(args[0].val);
            let cty = self.ty_of(cause);
            let f = self.cx.category_fn(self.b.m, cty, result);
            let v = self.b.call(f, &[cause]);
            return Ok(Val { v, own: true });
        }
        if native == "shared/share" {
            // The payload moves into a refcounted box; copies of the handle retain it.
            let payload = self.owned(args[0].val);
            let v = self.shared_new(payload, result);
            return Ok(Val { v, own: true });
        }
        if native == "collections/map_from_entries" {
            return self.map_from_entries(args[0].val, result);
        }
        if matches!(native, "crypto/sha256" | "crypto/sha384" | "crypto/sha512") {
            // The digest of the `HashAlgorithm` case of that name.
            let data = args
                .first()
                .ok_or_else(|| Error::new("a digest without data"))?;
            let data = self.borrow(data.val);
            let alg = match native {
                "crypto/sha256" => 3,
                "crypto/sha384" => 4,
                _ => 5,
            };
            let alg = self.b.iconst(alg);
            let sym = "msrt_crypto_digest";
            let sig = crate::rtcall::rt_sig(sym)
                .ok_or_else(|| Error::new(format!("no runtime symbol {sym}")))?;
            return self.finish_rt_call(sym, &sig, true, vec![alg, data], MTy::BYTES);
        }
        if native == "crypto/derive_key" {
            // PBKDF2-HMAC-SHA-256: the `HashAlgorithm.Sha256` case of the algorithm method.
            let mut vals = vec![self.b.iconst(3)];
            for a in args {
                vals.push(self.borrow(a.val));
            }
            let sym = "msrt_crypto_derive_key";
            let sig = crate::rtcall::rt_sig(sym)
                .ok_or_else(|| Error::new(format!("no runtime symbol {sym}")))?;
            return self.finish_rt_call(sym, &sig, true, vals, result);
        }
        let sym = crate::rtcall::function_symbol(native)
            .ok_or_else(|| Error::new(format!("unsupported native function {native}")))?;
        self.rt_function(&sym, params, args, result)
    }

    /// Whether `a` orders strictly above `b`; Float orders NaN above every other value.
    fn strictly_above(&mut self, a: Value, b: Value) -> Result<Value, Error> {
        use ms_mir::ir::{Cc, Op};
        let t = self.ty_of(a);
        let above = if self.b.m.types.is_int(t) {
            self.b.icmp(Cc::Gt, a, b)
        } else if self.b.m.types.is_float(t) {
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
        Ok(above)
    }

    /// `max(left, right)` / `min(left, right)`: `left` unless `right` is strictly greater
    /// (lesser). Floats order NaN above every other value.
    fn min_max(&mut self, max: bool, args: &[NArg]) -> Result<Val, Error> {
        let (left, right) = (self.borrow(args[0].val), self.borrow(args[1].val));
        let t = self.ty_of(left);
        // `a` ordered strictly above `b`.
        let (a, b) = if max { (right, left) } else { (left, right) };
        let above = self.strictly_above(a, b)?;
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

    /// The `@std/math` bit operations on `Int` as single MIR instructions. A shift count outside
    /// 0 through 63 goes to the runtime function of the same name, which faults.
    fn bit_operation(&mut self, name: &str, args: &[NArg]) -> Result<Val, Error> {
        use ms_mir::ir::{Cc, Op};
        let left = self.borrow(args[0].val);
        let v = match name {
            "bit_not" => {
                let ones = self.b.iconst(-1);
                self.b.binop(Op::Xor, left, ones)
            }
            "bit_and" | "bit_or" | "bit_xor" | "wrapping_add" | "wrapping_subtract"
            | "wrapping_multiply" => {
                let right = self.borrow(args[1].val);
                let op = match name {
                    "bit_and" => Op::And,
                    "bit_or" => Op::Or,
                    "bit_xor" => Op::Xor,
                    "wrapping_add" => Op::IAdd,
                    "wrapping_subtract" => Op::ISub,
                    _ => Op::IMul,
                };
                self.b.binop(op, left, right)
            }
            _ => {
                let count = self.borrow(args[1].val);
                let (zero, max) = (self.b.iconst(0), self.b.iconst(63));
                let lo = self.b.icmp(Cc::Ge, count, zero);
                let hi = self.b.icmp(Cc::Le, count, max);
                let ok = self.b.binop(Op::And, lo, hi);
                let (good, bad) = (self.b.new_block(), self.b.new_block());
                self.b.br_if(ok, good, &[], bad, &[]);
                self.b.seal_block(good);
                self.b.seal_block(bad);
                self.b.switch_to(bad);
                let ext = self.b.m.add_extern(ms_mir::ir::ExternDef {
                    name: format!("msrt_bits_{name}"),
                    params: vec![
                        Param {
                            ty: MTy::INT,
                            mode: Mode::Borrow
                        };
                        2
                    ],
                    ret: MTy::INT,
                    noreturn: true,
                    pure_: false,
                    fresh: false,
                });
                self.b.call_rt(ext, &[left, count]);
                self.b.unreachable();
                self.b.switch_to(good);
                match name {
                    "shift_left" => self.b.binop(Op::Shl, left, count),
                    "shift_right" => self.b.binop(Op::Sshr, left, count),
                    _ => {
                        // Logical shift: clear the sign bit after one arithmetic step, then
                        // shift the rest; a zero count leaves the value alone.
                        let (one, max) = (self.b.iconst(1), self.b.iconst(i64::MAX));
                        let half = self.b.binop(Op::Sshr, left, one);
                        let half = self.b.binop(Op::And, half, max);
                        let rest = self.b.binop(Op::ISub, count, one);
                        let shifted = self.b.binop(Op::Sshr, half, rest);
                        let is_zero = self.b.icmp(Cc::Eq, count, zero);
                        self.b.select(is_zero, left, shifted)
                    }
                }
            }
        };
        Ok(Val { v, own: false })
    }

    /// `stdout()` / `stderr()`: an interface value over a MIR-built vtable.
    pub(crate) fn std_stream(&mut self, it: MTy, stderr: bool) -> Result<Val, Error> {
        let name = if stderr { "stderr" } else { "stdout" };
        self.native_iface(it, name, &mut |m, method, params, ret| {
            build_stream_method(m, method, params, ret, stderr)
        })
    }

    /// `clock()` / `wall_clock()`: an interface whose `now` reads the runtime clock.
    pub(crate) fn time_clock(&mut self, it: MTy, wall: bool) -> Result<Val, Error> {
        let name = if wall { "wall_clock" } else { "clock" };
        self.native_iface(it, name, &mut |m, method, params, ret| {
            build_clock_method(m, method, params, ret, wall)
        })
    }

    /// An interface value of the expression's type over a vtable of MIR-built methods.
    fn native_iface(
        &mut self,
        it: MTy,
        name: &str,
        build: &mut MethodBuilder<'_>,
    ) -> Result<Val, Error> {
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
                self.cx
                    .intern_vtable(self.b.m, key, iface, methods, MTy::UNIT)
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

    /// A method of a format enum (`ArchiveFormat.pack`): the runtime takes the format as a
    /// parameter after the first declared one, spelled as the lowercase case name or as its index.
    /// `map_from_entries(entries)`: later entries replace earlier values for a repeated key.
    fn map_from_entries(&mut self, entries: Val, map: MTy) -> Result<Val, Error> {
        let list = self.borrow(entries);
        let lt = self.ty_of(list);
        let TyKind::List(entry) = self.b.m.types.kind(lt).clone() else {
            return Err(Error::new("map_from_entries takes a list"));
        };
        let TyKind::Rec(rid) = self.b.m.types.kind(entry).clone() else {
            return Err(Error::new("map_from_entries takes entry records"));
        };
        let lvar = self.fresh_var(lt);
        let held = self.owned(Val {
            v: list,
            own: false,
        });
        self.b.def_var(lvar, held);
        let acc = self.fresh_var(map);
        let fresh = self.map_new(map)?;
        self.b.def_var(acc, fresh);
        self.each_element(lvar, &mut |s, _, item| {
            let (k, v) = (s.b.rec_get(rid, 0, item), s.b.rec_get(rid, 1, item));
            let k = s.owned(Val { v: k, own: false });
            let v = s.owned(Val { v, own: false });
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
            .map(|c| c.name.as_str().to_lowercase())
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
        let name = ct::Name::from(param);
        args.push(NArg {
            name,
            val,
            wrapped: false,
        });
        let first =
            m.ty.params
                .first()
                .ok_or_else(|| Error::new("format method without arguments"))?
                .clone();
        let mut decl = vec![first.clone()];
        decl.push(ct::Param { name, ty: first.ty });
        decl.extend(m.ty.params.iter().skip(1).cloned());
        self.rt_function(sym, &decl, &args, result)
    }

    /// Whether an argument of the call assigns the variable at the root of the receiver place.
    fn argument_reassigns(&self, recv_expr: &Expr, view: &CallView<'_>) -> bool {
        if !self.is_place(recv_expr) {
            return false;
        }
        let Some(uid) = crate::mutation::place_root(&self.hir, recv_expr) else {
            return false;
        };
        view.arguments.iter().any(|a| {
            crate::mutation::mutated_locals(
                &self.hir,
                ms_check::hir::Body::Expr(a.expr),
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
            "format_int" => {
                let radix = self.borrow(args[0].val);
                self.call_runtime("msrt_uint_to_string_radix", &[v, radix], MTy::STR)?
            }
            "compare_int" => {
                let other = self.borrow(args[0].val);
                self.call_runtime("msrt_uint_compare", &[v, other], MTy::INT)?
            }
            "to_decimal" => self.call_runtime("msstd_decimal_from_uint", &[v], result)?,
            _ => return Ok(None),
        };
        Ok(Some(Val {
            v: out,
            own: name != "compare_int",
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
                self.call_runtime("msrt_uint_to_float", &[x], MTy::FLOAT)?
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

    pub fn native_method(
        &mut self,
        e: &Expr,
        view: &CallView<'_>,
        m: &ct::MethodRef,
        recv_expr: &Expr,
        recv: Val,
    ) -> Result<Val, Error> {
        let native = m.native.as_str();
        let at = self.b.current();
        // The receiver is evaluated first: an argument that reassigns its variable must not
        // change what the call reads.
        let snapshot = self.argument_reassigns(recv_expr, view);
        let recv = if snapshot {
            let v = self.owned(recv);
            self.hold_temp(Val { v, own: true })
        } else if recv.own
            && view
                .arguments
                .iter()
                .any(|a| crate::mutation::has_try(a.expr))
        {
            // A `try` in an argument may return early: the receiver is released by then.
            self.hold_temp(recv)
        } else {
            recv
        };
        let mut args = self.native_args(view)?;
        if self.dead {
            return Ok(recv);
        }
        let recv = if snapshot {
            recv
        } else {
            self.refresh(recv_expr, recv, at)?
        };
        let func = m.decl.as_ref().and_then(|d| d.func());
        self.fill_native_defaults(m.module, func, &m.ty.params, &mut args)?;
        self.at(e.pos);
        if let Some(sym) = hash_algorithm_symbol(native) {
            let result = self.emty(e)?;
            return self.hash_algorithm_call(sym, recv, &args, result);
        }
        if native == "string/chars" && self.chars_iter_for == Some(e as *const Expr) {
            // `for c in text.chars()`: the loop scans the string itself, so no list is built.
            self.chars_iter_for = None;
            return Ok(recv);
        }
        if native == "string/scalar_values" && self.chars_iter_for == Some(e as *const Expr) {
            // `for c in text.scalar_values()`: the loop decodes the string itself.
            self.chars_iter_for = None;
            self.scalars_scan = true;
            return Ok(recv);
        }
        if self.map_walk_for == Some(e as *const Expr)
            && let Some(walk) = self.walk_kind(m, recv.v)
        {
            // `for e in m.entries()` over a map the loop cannot change: the loop walks the
            // map's slots, so no list is built and nothing is copied.
            self.map_walk_for = None;
            self.map_walk = Some(walk);
            return Ok(recv);
        }
        if self.keys_view_for == Some(e as *const Expr)
            && let Some(sym) = self.keys_view_symbol(m, recv_expr, recv.v)
        {
            // `for k in p.m.keys()` over a map in a parameter the body only reads: the list
            // borrows the map's strings instead of copying them.
            self.keys_view_for = None;
            let result = self.emty(e)?;
            return self.rt_method(sym, recv, &[], &[], result);
        }
        if native == "string/split"
            && self.split_view_for == Some(e as *const Expr)
            && self.stable_place(recv_expr)
        {
            // `let parts = text.split(..)` read only in place, over a parameter the body only
            // reads: the pieces are views of `text`.
            self.split_view_for = None;
            let result = self.emty(e)?;
            return self.rt_method("msrt_string_split_view", recv, &m.ty.params, &args, result);
        }
        if native == "string/split" && self.split_iter_for == Some(e as *const Expr) {
            // `for piece in text.split(..)`: pieces are produced one at a time.
            self.split_iter_for = None;
            let iter = self.b.m.types.obj("SplitIter", Vec::new());
            return self.rt_method("msrt_string_split_iter", recv, &m.ty.params, &args, iter);
        }
        if let Some(decode) = match native {
            "archive/format_compress_stream" => Some(false),
            "archive/format_decompress_stream" => Some(true),
            _ => None,
        } {
            let result = self.emty(e)?;
            let name = self.format_argument(m, recv, false)?;
            return self.codec_stream(name, &args, decode, result);
        }
        if let Some(&(_, sym, param, as_text)) = FORMAT_METHODS.iter().find(|(n, ..)| *n == native)
        {
            let result = self.emty(e)?;
            return self.format_method(result, m, recv, args, (sym, param, as_text));
        }
        if native == "hash" && !matches!(self.b.m.types.kind(self.ty_of(recv.v)), TyKind::Str) {
            return self.structural_hash(recv);
        }
        if let Some((_, sym)) = STRING_TO_STRING.iter().find(|(n, _)| *n == native) {
            let r = self.borrow(recv);
            let out = self.call_runtime(sym, &[r], MTy::STR)?;
            return Ok(Val { v: out, own: true });
        }
        if native == "string/length" || native == "string/scalar_length" {
            let r = self.borrow(recv);
            let n = self.b.str_len(r);
            return Ok(Val { v: n, own: false });
        }
        if let Some((_, sym, ret)) = PLAIN_STRING.iter().find(|(n, _, _)| *n == native) {
            let mut vals = vec![self.borrow(recv)];
            for a in args {
                vals.push(self.borrow(a.val));
            }
            let out = self.call_runtime(sym, &vals, *ret)?;
            return Ok(self.val(out, *ret == MTy::STR));
        }
        if native == "core/message" {
            let concrete = self.ety(recv_expr);
            let data = self.ty_of(recv.v);
            let f = self
                .cx
                .native_method_fn(self.b.m, native, &concrete, data)?;
            let r = self.borrow(recv);
            let text = self.b.call(f, &[r]);
            return Ok(Val { v: text, own: true });
        }
        if native == "string/form_normalize" {
            // The form is a payload-free alternative: its case index selects the algorithm.
            let result = self.emty(e)?;
            let find = |n: &str| args.iter().find(|a| a.name.as_str() == n).copied();
            let text = find("text").ok_or_else(|| Error::new("normalize without text"))?;
            let text = self.borrow(text.val);
            let form = self.borrow(recv);
            let kind = self.b.alt_tag(form);
            let (has, max) = self.optional_int(find("max_bytes"))?;
            let sym = "msrt_string_normalize_kind";
            let sig = crate::rtcall::rt_sig(sym)
                .ok_or_else(|| Error::new(format!("no runtime symbol {sym}")))?;
            return self.finish_rt_call(sym, &sig, true, vec![text, kind, has, max], result);
        }
        let pos = e.pos;
        let result = self.emty(e)?;
        self.native_method_tail(m, Some(recv_expr), pos, result, recv, args)
    }

    /// The part of a native method call that needs only the receiver, the arguments and the
    /// result type, so a bound method value reaches it without a call expression.
    pub(crate) fn native_method_tail(
        &mut self,
        m: &ct::MethodRef,
        recv_expr: Option<&Expr>,
        pos: ms_syntax::Pos,
        result: MTy,
        recv: Val,
        mut args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let native = m.native.as_str();
        let recv_ty = self.ty_of(recv.v);
        let numeric_recv = self.b.m.types.is_int(recv_ty) || self.b.m.types.is_float(recv_ty);
        // `Float.to_float32()` is a runtime call: it returns none when the value overflows.
        let float_to_float32 = native == "to_float32" && self.b.m.types.is_float(recv_ty);
        if (matches!(
            native,
            "to_int8"
                | "to_int16"
                | "to_int32"
                | "to_int64"
                | "to_uint8"
                | "to_uint16"
                | "to_uint32"
                | "to_uint64"
                | "to_float32"
                | "to_float64"
        ) || (numeric_recv && matches!(native, "to_int" | "to_float")))
            && !float_to_float32
        {
            return self.numeric_conversion(result, recv);
        }
        if recv_ty == MTy::UINT64
            && let Some(v) = self.uint64_method(native, result, recv, &args)?
        {
            return Ok(v);
        }
        // Other operations on a sized number run on its 64-bit kind; a clone keeps its width.
        let recv_nums = {
            let t = self.ty_of(recv.v);
            (self.b.m.types.is_int(t) || self.b.m.types.is_float(t))
                && native.rsplit('/').next() != Some("clone")
        };
        let recv = if recv_nums {
            for a in &mut args {
                a.val = self.widen_numeric(a.val);
            }
            self.widen_numeric(recv)
        } else {
            recv
        };
        if let Some(sym) = m
            .name()
            .and_then(|n| crate::rtcall::typed_method_symbol(&m.receiver, n.as_str()))
        {
            return self.rt_method(&sym, recv, &m.ty.params, &args, result);
        }
        let name = native.rsplit('/').next().unwrap_or(native);
        let rty = self.ty_of(recv.v);
        // `map_add`, `set_values`: the receiver type already says which.
        // `Map.map_keys` is itself the method's name, which the `map_` rule would cut.
        let keep = name == "map_keys";
        let name = if !keep && crate::mapset::is_map_or_set(self.b.m, rty) {
            name.strip_prefix("map_")
                .or_else(|| name.strip_prefix("set_"))
                .unwrap_or(name)
        } else {
            name
        };
        match (self.b.m.types.kind(rty).clone(), name) {
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
                self.map_get_or(recv, &m.ty.params, &args, result)
            }
            (TyKind::Obj(n, _), "entries") if n == "Map" => {
                self.map_entries(recv_expr, recv, result)
            }
            (TyKind::List(_), "list_keys") => self.list_keys(recv_expr, recv, result),
            (TyKind::List(_), "entries") => self.list_entries(recv_expr, recv, result),
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
            (TyKind::List(_), "zip") => {
                let TyKind::List(pair) = self.b.m.types.kind(result).clone() else {
                    return Err(Error::new("zip without a list result"));
                };
                let TyKind::Rec(rid) = self.b.m.types.kind(pair).clone() else {
                    return Err(Error::new("zip without a record element"));
                };
                let other = self.borrow(args[0].val);
                let other_len = self.b.list_len(other);
                // Zipping a list with itself must not iterate its variable, which loop headers
                // would consume while `other` is still read.
                let same = other == recv.v;
                let (lv, hidden) = self.list_source(if same { None } else { recv_expr }, recv)?;
                let acc = self.fresh_var(result);
                let first = self.b.list_new(pair, other_len);
                self.b.def_var(acc, first);
                self.each_element(lv, &mut |s, i, x| {
                    let inside = s.b.icmp(ms_mir::ir::Cc::Lt, i, other_len);
                    let (take, skip) = (s.b.new_block(), s.b.new_block());
                    s.b.br_if(inside, take, &[], skip, &[]);
                    s.b.seal_block(take);
                    s.b.seal_block(skip);
                    s.b.switch_to(take);
                    let y = s.b.list_get(other, i);
                    let xo = s.owned(Val { v: x, own: false });
                    let yo = s.owned(Val { v: y, own: false });
                    let rec = s.b.rec_new(rid, &[xo, yo]);
                    let cur = s.b.use_var(acc);
                    let next = s.b.list_push(cur, rec);
                    s.b.def_var(acc, next);
                    s.b.br(skip, &[]);
                    s.b.switch_to(skip);
                    Ok(None)
                })?;
                self.release_source(lv, hidden);
                let out = self.b.use_var(acc);
                Ok(Val { v: out, own: true })
            }
            (TyKind::List(elem), "chunks" | "windows") => {
                self.list_pieces(name == "chunks", elem, recv, &args, result)
            }
            (TyKind::List(elem), "get") => {
                // Arguments arrive in written order; the names say which is which.
                let mut index = None;
                let mut default = None;
                for a in args {
                    if a.name.as_str() == "default" {
                        default = Some(a);
                    } else {
                        index = Some(a);
                    }
                }
                let index = index.ok_or_else(|| Error::new("get without index"))?;
                self.list_get_or(recv, elem, index, default)
            }
            (_, "abs_int" | "sign_int") => {
                let x = self.borrow(recv);
                let (zero, minus) = (self.b.iconst(0), self.b.iconst(-1));
                let neg = self.b.icmp(ms_mir::ir::Cc::Lt, x, zero);
                if name == "sign_int" {
                    let (one, pos) = (self.b.iconst(1), self.b.icmp(ms_mir::ir::Cc::Gt, x, zero));
                    let upper = self.b.select(pos, one, zero);
                    let v = self.b.select(neg, minus, upper);
                    return Ok(Val { v, own: false });
                }
                let negated = self.b.binop(ms_mir::ir::Op::ISubChk, zero, x);
                let v = self.b.select(neg, negated, x);
                // A narrower receiver keeps its type; the range check faults on its minimum.
                let v = if self.b.m.types.int_bits(result).is_some_and(|b| b < 64) {
                    let narrow = self.b.conv(v, result);
                    self.b.narrow_chk(narrow)
                } else {
                    v
                };
                Ok(Val { v, own: false })
            }
            (_, "abs_float" | "sign_float") => {
                let x = self.borrow(recv);
                let v = if name == "abs_float" {
                    self.b
                        .emit(
                            ms_mir::ir::Op::FAbs,
                            &[x],
                            ms_mir::ir::Imm::None,
                            Some(MTy::FLOAT),
                        )
                        .expect("fabs")
                } else {
                    self.call_runtime("msstd_math_sign", &[x], MTy::FLOAT)?
                };
                let v = if result == MTy::FLOAT32 {
                    self.b.conv(v, result)
                } else {
                    v
                };
                Ok(Val { v, own: false })
            }
            (TyKind::Int, "to_decimal") => {
                let n = self.borrow(recv);
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
                // An unordered pair has a NaN: NaN equals NaN and sorts above every other value.
                let unordered = if name == "compare_float" {
                    let a_nan = self.b.fcmp(ms_mir::ir::Cc::Ne, a, a);
                    let b_nan = self.b.fcmp(ms_mir::ir::Cc::Ne, b, b);
                    let a_only = self.b.select(b_nan, zero, one);
                    let b_only = self.b.select(b_nan, m1, zero);
                    self.b.select(a_nan, a_only, b_only)
                } else {
                    zero
                };
                let g = self.b.select(gt, one, unordered);
                let v = self.b.select(lt, m1, g);
                Ok(Val { v, own: false })
            }
            (TyKind::Opt(inner), _) if opt_method(name) => {
                let out = result;
                self.optional_method(out, pos, name, recv, inner, args)
            }
            (
                TyKind::Alt(a),
                "get" | "err" | "get_or_else" | "or_else" | "map_error" | "map" | "and_then"
                | "to_optional",
            ) => {
                let out = result;
                self.result_method(out, name, recv, a, args)
            }
            (TyKind::Alt(a), "is_ok" | "is_error") => self.result_state(name, recv, a),
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
            (_, "to_string") if m.receiver.is_time("Duration") => self.duration_text(recv),
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
            (TyKind::List(elem), "sorted") => self.list_sorted_call(recv_expr, recv, elem, args),
            (_, "equals") if args.len() == 1 => {
                let concrete = recv_expr.map_or_else(|| m.receiver.clone(), |r| self.hir.ty(r));
                self.equals_value(&concrete, recv, args[0].val)
            }
            _ if crate::iterate::handles(self.b.m, rty, name) => {
                let out = result;
                self.iterate_method(out, name, recv_expr, recv, args)
            }
            (TyKind::List(_), _) if is_higher_order(name) => {
                let out = result;
                self.list_higher(name, out, recv_expr, recv, args)
            }
            _ => {
                let Some(sym) = crate::rtcall::method_symbol(self.b.m, rty, native) else {
                    return Err(Error::new(format!(
                        "unsupported native method {native} ({name}) on {}",
                        ms_mir::print::ty_str(self.b.m, rty)
                    )));
                };
                self.rt_method(&sym, recv, &m.ty.params, &args, result)
            }
        }
    }

    /// A list method taking a function (`map`, `count`, `for_each`, ...).
    fn list_higher(
        &mut self,
        name: &str,
        out: MTy,
        recv_expr: Option<&Expr>,
        recv: Val,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let TyKind::List(elem) = self.b.m.types.kind(self.ty_of(recv.v)).clone() else {
            return Err(Error::new("higher-order method on a non-list"));
        };
        let f = args
            .into_iter()
            .find(|a| self.is_fn(a.val.v))
            .ok_or_else(|| Error::new("missing function argument"))?;
        let ft = self.ty_of(f.val.v);
        let fvar = self.fresh_var(ft);
        let fo = self.owned(f.val);
        self.b.def_var(fvar, fo);
        let (lv, hidden) = self.list_source(recv_expr, recv)?;
        let r = self.list_higher_order(name, lv, elem, fvar, out);
        self.release_source(lv, hidden);
        self.release_source(fvar, true);
        r
    }

    /// `result.is_ok()` or `result.is_error()`.
    fn result_state(
        &mut self,
        name: &str,
        recv: Val,
        alt: ms_mir::types::AltId,
    ) -> Result<Val, Error> {
        let want = if name == "is_ok" { "ok" } else { "error" };
        let case = self.b.m.alts[alt.index()]
            .cases
            .iter()
            .position(|c| c.name == want)
            .ok_or_else(|| Error::new("Result without ok/error cases"))?;
        let tag = self.b.alt_tag(recv.v);
        let k = self.b.iconst(case as i64);
        let v = self.b.icmp(ms_mir::ir::Cc::Eq, tag, k);
        // Only read: an owned result holding a resource (`open().is_ok()`) closes it.
        self.close_owned_temp(recv);
        self.finish(recv);
        Ok(Val { v, own: false })
    }

    /// A collection mutator applied in place to the variable at `slot`, for a method value
    /// that shares its receiver.
    pub(crate) fn shared_native_call(
        &mut self,
        m: &ct::MethodRef,
        slot: Value,
        rty: MTy,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let name = m.name().map(|n| n.to_string()).unwrap_or_default();
        let old = self.move_out(slot, rty);
        let (new, r) = self.mutate_any(&name, old, &m.ty.params, args, true, result)?;
        self.move_into(slot, new);
        if result == MTy::UNIT {
            if let Some(r) = r.filter(|r| r.own) {
                self.drop_value(r.v);
            }
            return Ok(Val {
                v: self.b.unit(),
                own: false,
            });
        }
        r.ok_or_else(|| Error::new("a collection mutator without a result"))
    }

    /// A native method applied to evaluated arguments, for method values.
    pub(crate) fn bound_native_call(
        &mut self,
        m: &ct::MethodRef,
        recv: Val,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let rty = self.ty_of(recv.v);
        let name = m.name().map(|n| n.to_string()).unwrap_or_default();
        if let Some(&(_, sym, param, as_text)) = FORMAT_METHODS
            .iter()
            .find(|(n, ..)| *n == m.native.as_str())
        {
            return self.format_method(result, m, recv, args.to_vec(), (sym, param, as_text));
        }
        if ms_check::effects::collection_mutation(m) {
            // The bound receiver is a copy: the mutated collection is the result.
            let b = self.borrow(recv);
            let old = self.owned(Val { v: b, own: false });
            let (new, r) = self.mutate_any(&name, old, &m.ty.params, args, true, result)?;
            if result == MTy::UNIT {
                self.drop_value(new);
                if let Some(r) = r.filter(|r| r.own) {
                    self.drop_value(r.v);
                }
                return Ok(Val {
                    v: self.b.unit(),
                    own: false,
                });
            }
            return Ok(match r {
                Some(r) => {
                    self.drop_value(new);
                    r
                }
                None => Val { v: new, own: true },
            });
        }
        if name == "clone" {
            let v = self.owned(Val {
                v: recv.v,
                own: false,
            });
            return Ok(Val { v, own: true });
        }
        if m.native.as_str() == "core/message" {
            let data = self.ty_of(recv.v);
            let f = self
                .cx
                .native_method_fn(self.b.m, m.native.as_str(), &m.receiver, data)?;
            let r = self.borrow(recv);
            let text = self.b.call(f, &[r]);
            return Ok(Val { v: text, own: true });
        }
        if let (TyKind::Alt(a), "is_ok" | "is_error") =
            (self.b.m.types.kind(rty).clone(), name.as_str())
        {
            return self.result_state(&name, recv, a);
        }
        if let (
            TyKind::Alt(a),
            "get" | "err" | "get_or_else" | "or_else" | "map_error" | "map" | "and_then"
            | "to_optional",
        ) = (self.b.m.types.kind(rty).clone(), name.as_str())
        {
            return self.result_method(result, &name, recv, a, args.to_vec());
        }
        if let (TyKind::Opt(inner), true) = (self.b.m.types.kind(rty).clone(), opt_method(&name)) {
            let at = ms_syntax::Pos::default();
            return self.optional_method(result, at, &name, recv, inner, args.to_vec());
        }
        if let (TyKind::Obj(n, _), "get_or") = (self.b.m.types.kind(rty).clone(), name.as_str())
            && n == "Map"
        {
            return self.map_get_or(recv, &m.ty.params, args, result);
        }
        if let (TyKind::List(elem), "get") = (self.b.m.types.kind(rty).clone(), name.as_str()) {
            let find = |want: bool| args.iter().find(|a| (a.name.as_str() == "default") == want);
            let index = find(false)
                .copied()
                .ok_or_else(|| Error::new("get without index"))?;
            return self.list_get_or(recv, elem, index, find(true).copied());
        }
        if crate::iterate::handles(self.b.m, rty, &name) {
            return self.iterate_method(result, &name, None, recv, args.to_vec());
        }
        if matches!(self.b.m.types.kind(rty), TyKind::List(_)) && is_higher_order(&name) {
            return self.list_higher(&name, result, None, recv, args.to_vec());
        }
        if let (TyKind::List(elem), "take" | "drop") =
            (self.b.m.types.kind(rty).clone(), name.as_str())
        {
            let sym = if name == "take" {
                "msrt_list_take"
            } else {
                "msrt_list_drop_n"
            };
            let d = self.type_desc(elem);
            let r = self.borrow(recv);
            let n = self.borrow(args[0].val);
            let out = self.call_runtime(sym, &[r, d, n], rty)?;
            return Ok(Val { v: out, own: true });
        }
        if let Some(sym) = hash_algorithm_symbol(m.native.as_str()) {
            return self.hash_algorithm_call(sym, recv, args, result);
        }
        if m.native.as_str() == "hash" && !matches!(self.b.m.types.kind(rty), TyKind::Str) {
            return self.structural_hash(recv);
        }
        self.native_method_tail(
            m,
            None,
            ms_syntax::Pos::default(),
            result,
            recv,
            args.to_vec(),
        )
    }

    /// `equals` of data with built-in equality: the equality `==` selects, against another
    /// value of the same type.
    fn equals_value(&mut self, _concrete: &ct::Ty, recv: Val, other: Val) -> Result<Val, Error> {
        let t = self.ty_of(recv.v);
        // `equal` borrows both operands, so owned temporaries are released with the statement.
        let v = self.equal(t, recv, other)?;
        Ok(Val { v, own: false })
    }

    /// A `HashAlgorithm` operation: the algorithm is the receiver's case index, the first runtime argument.
    fn hash_algorithm_call(
        &mut self,
        sym: &str,
        recv: Val,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let tag = self.borrow(recv);
        let alg = self.b.alt_tag(tag);
        let mut vals = vec![alg];
        for a in args {
            vals.push(self.borrow(a.val));
        }
        let sig = crate::rtcall::rt_sig(sym)
            .ok_or_else(|| Error::new(format!("no runtime symbol {sym}")))?;
        let has_out = sig.params.last().is_some_and(|p| p.name == "out");
        self.finish_rt_call(sym, &sig, has_out, vals, result)
    }

    /// A variable that always holds the receiver list, for use across loop headers.
    /// The flag says the variable is a hidden copy to drop afterwards.
    pub(crate) fn list_source(
        &mut self,
        recv_expr: Option<&Expr>,
        recv: Val,
    ) -> Result<(ms_mir::builder::Var, bool), Error> {
        if let Some(Resolution::Local(b)) = recv_expr.map(|r| self.hir.resolution(r))
            && !self.aliases.contains_key(&b.uid)
            && self.local(&b)?.slot.is_none()
        {
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

    /// `sorted(compare)`: a stable sort of a copy ordered by the comparator's sign.
    fn list_sorted_call(
        &mut self,
        recv_expr: Option<&Expr>,
        recv: Val,
        elem: MTy,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let f = args
            .into_iter()
            .next()
            .ok_or_else(|| Error::new("sorted without comparator"))?;
        if !self.is_fn(f.val.v) {
            return Err(Error::new(
                "sorted takes a comparator function; omit compare to sort in natural order",
            ));
        }
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

    /// The indexes of a list: `0..length`.
    fn list_keys(
        &mut self,
        recv_expr: Option<&Expr>,
        recv: Val,
        result: MTy,
    ) -> Result<Val, Error> {
        let (lv, hidden) = self.list_source(recv_expr, recv)?;
        let n = {
            let l = self.b.use_var(lv);
            self.b.list_len(l)
        };
        let acc = self.fresh_var(result);
        let first = self.b.list_new(MTy::INT, n);
        self.b.def_var(acc, first);
        self.each_element(lv, &mut |s, i, _| {
            let cur = s.b.use_var(acc);
            let next = s.b.list_push(cur, i);
            s.b.def_var(acc, next);
            Ok(None)
        })?;
        self.release_source(lv, hidden);
        let out = self.b.use_var(acc);
        Ok(Val { v: out, own: true })
    }

    /// `chunks(size)` (steps by `size`, keeps a short tail) or `windows(size)` (steps by one).
    fn list_pieces(
        &mut self,
        chunks: bool,
        elem: MTy,
        recv: Val,
        args: &[NArg],
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::List(inner) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("pieces without a list result"));
        };
        let d = self.type_desc(elem);
        let od = self.type_desc(inner);
        let r = self.borrow(recv);
        let size = self.borrow(args[0].val);
        let step = if chunks { size } else { self.b.iconst(1) };
        let short = self.b.bconst(chunks);
        let out = self.call_runtime("msrt_list_pieces", &[r, d, od, size, step, short], result)?;
        Ok(Val { v: out, own: true })
    }

    /// A stable merge sort of a copy (the runtime's), ordered by the comparator's sign.
    fn list_sorted(
        &mut self,
        lv: ms_mir::builder::Var,
        fvar: ms_mir::builder::Var,
        elem: MTy,
    ) -> Result<Val, Error> {
        let l = self.b.use_var(lv);
        let f = self.b.use_var(fvar);
        let thunk = self.sort_thunk(elem, self.ty_of(f));
        let cmp = self
            .b
            .emit(
                ms_mir::ir::Op::FuncAddr,
                &[],
                ms_mir::ir::Imm::Func(thunk),
                Some(MTy::PTR),
            )
            .expect("func.addr");
        let d = self.type_desc(elem);
        let t = self.ty_of(l);
        let out = self.call_runtime("msrt_list_sorted", &[l, d, cmp, f], t)?;
        Ok(Val { v: out, own: true })
    }

    /// `fn(comparator, ptr, ptr) -> int` for the runtime sort: loads the two element slots and
    /// calls the source comparator on them.
    fn sort_thunk(&mut self, elem: MTy, closure: MTy) -> ms_mir::ir::FuncId {
        let p = |ty| Param {
            ty,
            mode: Mode::Borrow,
        };
        let mut tb = ms_mir::builder::FuncBuilder::new(
            self.b.m,
            "sort.cmp",
            vec![p(closure), p(MTy::PTR), p(MTy::PTR)],
            MTy::INT,
        );
        tb.func_mut().linkage = ms_mir::ir::Linkage::Internal;
        let args = tb.params();
        let mut load = |a| {
            tb.emit(
                ms_mir::ir::Op::Load,
                &[a],
                ms_mir::ir::Imm::Ty(elem),
                Some(elem),
            )
            .expect("load")
        };
        let (x, y) = (load(args[1]), load(args[2]));
        let r = tb.call_ind(args[0], &[x, y]);
        tb.ret(Some(r));
        let thunk = tb.into_func();
        self.b.m.add_func(thunk)
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
        // A mutator that discards an entry closes a resource in it first; the fast paths below
        // overwrite entries without a look at the old one.
        let discards = self.discards_resource(recv_expr, name)?;
        if !discards {
            if name == "add"
                && let Some(done) = self.fused_update(e, view, m, recv_expr)?
            {
                return Ok(done);
            }
            if let Some(done) = self.lent_key_add(e, view, m, recv_expr, name)? {
                return Ok(done);
            }
        }
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        if discards {
            self.close_discarded_entry(recv_expr, name, &args)?;
        }
        if name == "set"
            && !hands_back
            && let Some(done) = self.slot_list_set(recv_expr, &args)?
        {
            return Ok(done);
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

    /// Whether `name` on the place `recv_expr` discards a resource entry of a list or map:
    /// `set` and `remove` on a list of resources, `add`, `remove` and `clear` on a map of them.
    fn discards_resource(&mut self, recv_expr: &Expr, name: &str) -> Result<bool, Error> {
        if !matches!(name, "set" | "add" | "remove" | "clear" | "splice")
            || !self.is_place(recv_expr)
        {
            return Ok(false);
        }
        let ty = self.ety(recv_expr);
        let held = if ty.is_std("List") && matches!(name, "set" | "remove" | "splice") {
            ty.args.first()
        } else if ty.is_std("Map") && matches!(name, "add" | "remove" | "clear") {
            ty.args.get(1)
        } else {
            None
        };
        match held {
            Some(t) => Ok(self.part_closer(t)?.is_some()),
            None => Ok(false),
        }
    }

    /// Closes the entry `name` is about to discard from the place `recv_expr`.
    fn close_discarded_entry(
        &mut self,
        recv_expr: &Expr,
        name: &str,
        args: &[NArg],
    ) -> Result<(), Error> {
        let ty = self.ety(recv_expr);
        if name == "splice" {
            return self.close_list_range(recv_expr, &args[0], &args[1]);
        }
        if ty.is_std("List") {
            return self.close_list_entry(recv_expr, &args[0]);
        }
        if name == "clear" {
            // Every value goes: the map closes what it holds, last inserted first.
            let x = self.expr(recv_expr)?;
            if self.dead {
                return Ok(());
            }
            let map = self.borrow(x);
            self.close_discarded_ty(&ty, map)?;
            self.finish(x);
            return Ok(());
        }
        self.close_map_entry(recv_expr, &args[0])
    }

    /// `m.add(k, v)` over an existing key and `m.remove(k)` discard the value of `k`.
    fn close_map_entry(&mut self, recv_expr: &Expr, key: &NArg) -> Result<(), Error> {
        use ms_mir::ir::{Imm, Op};
        let ty = self.ety(recv_expr);
        let Some(value) = ty.args.get(1).cloned() else {
            return Ok(());
        };
        let x = self.expr(recv_expr)?;
        if self.dead {
            return Ok(());
        }
        let mv = self.borrow(x);
        let kv = self.borrow(key.val);
        let mt = self.ty_of(mv);
        let value_ty = self.map_value_type(mv)?;
        let (kd, vd) = self.map_descs(mt)?;
        let vd = vd.ok_or_else(|| Error::new("a set has no values"))?;
        let ks = self.lend_slot(kv);
        let p = self.call_runtime("msrt_map_get_ptr", &[mv, kd, vd, ks], MTy::PTR)?;
        let missing = self
            .b
            .emit(Op::PtrIsNull, &[p], Imm::None, Some(MTy::BOOL))
            .expect("is_null");
        let (absent, present) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(missing, absent, &[], present, &[]);
        self.b.seal_block(present);
        self.b.switch_to(present);
        let old = self
            .b
            .emit(Op::Load, &[p], Imm::Ty(value_ty), Some(value_ty))
            .expect("load");
        self.close_discarded_ty(&value, old)?;
        self.b.br(absent, &[]);
        self.b.seal_block(absent);
        self.b.switch_to(absent);
        self.finish(x);
        Ok(())
    }

    /// `xs.splice(start, count, ..)` deletes `count` elements from `start`: the resources in
    /// them close, last first. Bounds the mutator rejects close nothing and fault there.
    fn close_list_range(
        &mut self,
        recv_expr: &Expr,
        start: &NArg,
        count: &NArg,
    ) -> Result<(), Error> {
        use ms_mir::ir::{Cc, Mode, Op};
        let list_ty = self.ety(recv_expr);
        let Some(elem) = list_ty.args.first().cloned() else {
            return Ok(());
        };
        let x = self.expr(recv_expr)?;
        if self.dead {
            return Ok(());
        }
        let list = self.borrow(x);
        let from = self.borrow(start.val);
        let n = self.borrow(count.val);
        let len = self.b.list_len(list);
        let zero = self.b.iconst(0);
        let end = self.b.binop(Op::IAdd, from, n);
        let c1 = self.b.icmp(Cc::Ge, from, zero);
        let c2 = self.b.icmp(Cc::Ge, n, zero);
        let c3 = self.b.icmp(Cc::Le, end, len);
        let c12 = self.b.binop(Op::And, c1, c2);
        let valid = self.b.binop(Op::And, c12, c3);
        let (enter, exit) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(valid, enter, &[], exit, &[]);
        self.b.seal_block(enter);
        self.b.switch_to(enter);
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        self.b.def_var(idx, end);
        let (header, body, done) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(header, &[]);
        self.b.switch_to(header);
        let i = self.b.use_var(idx);
        let more = self.b.icmp(Cc::Gt, i, from);
        self.b.br_if(more, body, &[], done, &[]);
        self.b.seal_block(body);
        self.b.switch_to(body);
        let i = self.b.use_var(idx);
        let one = self.b.iconst(1);
        let j = self.b.binop(Op::ISub, i, one);
        self.b.def_var(idx, j);
        let e = self.b.list_get(list, j);
        self.close_discarded_ty(&elem, e)?;
        self.b.br(header, &[]);
        self.b.seal_block(header);
        self.b.seal_block(done);
        self.b.switch_to(done);
        self.b.br(exit, &[]);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        self.finish(x);
        Ok(())
    }

    /// `xs.set(i, v)` and `xs.remove(i)` discard the element at `i`: a resource in it closes
    /// first. An index out of range closes nothing and faults in the mutator.
    fn close_list_entry(&mut self, recv_expr: &Expr, index: &NArg) -> Result<(), Error> {
        use ms_mir::ir::{Cc, Op};
        let list_ty = self.ety(recv_expr);
        let Some(elem) = list_ty.args.first().filter(|_| list_ty.is_std("List")) else {
            return Ok(());
        };
        if self.part_closer(elem)?.is_none() {
            return Ok(());
        }
        let x = self.expr(recv_expr)?;
        if self.dead {
            return Ok(());
        }
        let list = self.borrow(x);
        let i = self.borrow(index.val);
        let n = self.b.list_len(list);
        let zero = self.b.iconst(0);
        let neg = self.b.icmp(Cc::Lt, i, zero);
        let shifted = self.b.binop(Op::IAdd, i, n);
        let r = self.b.select(neg, shifted, i);
        let lo = self.b.icmp(Cc::Ge, r, zero);
        let hi = self.b.icmp(Cc::Lt, r, n);
        let inside = self.b.binop(Op::And, lo, hi);
        let (yes, exit) = (self.b.new_block(), self.b.new_block());
        self.b.br_if(inside, yes, &[], exit, &[]);
        self.b.seal_block(yes);
        self.b.switch_to(yes);
        let e = self.b.list_get(list, r);
        self.close_discarded_ty(elem, e)?;
        self.b.br(exit, &[]);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        self.finish(x);
        Ok(())
    }

    /// `xs.set(i, v)` on a list variable that lives in memory (a closure shares it): the element
    /// is written where it lies. Taking the list out of its slot and putting the unchanged header
    /// back would store ptr, len and cap again after every write.
    fn slot_list_set(&mut self, recv_expr: &Expr, args: &[NArg]) -> Result<Option<Val>, Error> {
        use ms_mir::ir::{Cc, Imm, Op};
        let ExprKind::Name(_) = &recv_expr.kind else {
            return Ok(None);
        };
        let Resolution::Local(binding) = self.hir.resolution(recv_expr) else {
            return Ok(None);
        };
        if self.aliases.contains_key(&binding.uid) {
            return Ok(None);
        }
        let l = self.local(&binding)?;
        let (Some(_), TyKind::List(elem)) = (l.slot, self.b.m.types.kind(l.ty).clone()) else {
            return Ok(None);
        };
        let list = self.read_local(&binding)?.v;
        let i = self.borrow(args[0].val);
        let n = self.b.list_len(list);
        let zero = self.b.iconst(0);
        let neg = self.b.icmp(Cc::Lt, i, zero);
        let shifted = self.b.binop(Op::IAdd, i, n);
        let r = self.b.select(neg, shifted, i);
        self.check_index(2, i, r, n, false);
        let v = self.element_value(&args[1]);
        let at = self
            .b
            .emit(Op::ListAddrU, &[list, r], Imm::None, Some(MTy::PTR))
            .expect("list.addr.u");
        if self.needs_drop(elem) {
            let old = self
                .b
                .emit(Op::Take, &[at], Imm::Ty(elem), Some(elem))
                .expect("take");
            self.drop_value(old);
            self.b.emit(Op::Put, &[at, v], Imm::None, None);
        } else {
            self.b.emit(Op::Store, &[at, v], Imm::None, None);
        }
        let u = self.b.unit();
        Ok(Some(Val { v: u, own: false }))
    }

    /// Runs two branches that each produce an owned value of `ty` (or diverge with `None`).
    pub(crate) fn two_ways(
        &mut self,
        cond: Value,
        ty: MTy,
        yes: &mut BranchBody<'_, Self>,
        no: &mut BranchBody<'_, Self>,
    ) -> Result<Val, Error> {
        let mode = if self.needs_drop(ty) {
            Mode::Own
        } else {
            Mode::Borrow
        };
        self.two_ways_mode(cond, ty, mode, yes, no)
    }

    /// `two_ways` with the result's ownership chosen by the caller: `Borrow` joins two values
    /// that are borrows, so the result is one too.
    pub(crate) fn two_ways_mode(
        &mut self,
        cond: Value,
        ty: MTy,
        mode: Mode,
        yes: &mut BranchBody<'_, Self>,
        no: &mut BranchBody<'_, Self>,
    ) -> Result<Val, Error> {
        let owned = mode == Mode::Own;
        let out = self.b.declare_var(ty, mode);
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
    pub(crate) fn finish(&mut self, x: Val) {
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
            fresh: false,
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
            fresh: false,
        });
        self.b.call_rt(ext, &[msg]);
        self.b.unreachable();
        self.b.switch_to(good);
        let k = self.b.iconst(scale);
        let nanos = self.b.binop(Op::IMul, v, k);
        let out = self.duration_of(nanos)?;
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
            fresh: false,
        });
        self.b.call_rt(ext, &[]);
        self.b.unreachable();
    }

    fn optional_method(
        &mut self,
        out: MTy,
        at: ms_syntax::Pos,
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
                // Only read: an owned optional of a resource (`open().is_some()`) closes it.
                self.close_owned_temp(recv);
                self.finish(recv);
                Ok(Val { v, own: false })
            }
            "get" if args.is_empty() && self.needs_drop(inner) => {
                // The payload is a borrow of the optional, which stays alive as a temporary; a
                // consumer that keeps it copies it, and a `let` extends the temporary's life.
                let (good, bad) = (self.b.new_block(), self.b.new_block());
                self.b.br_if(some, good, &[], bad, &[]);
                self.b.seal_block(good);
                self.b.seal_block(bad);
                self.b.switch_to(bad);
                self.b.fault(ms_mir::ir::FaultKind::NoneUnwrap);
                self.b.switch_to(good);
                let p = self.b.opt_get(r);
                self.borrow(recv);
                Ok(Val { v: p, own: false })
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
                            // The default goes unused: an owned resource there closes now.
                            if d.wrapped {
                                s.close_owned_temp(d.val);
                            }
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
                                s.finish(d.val);
                                p
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
            "get_or_else" => {
                let f = args
                    .first()
                    .copied()
                    .ok_or_else(|| Error::new("missing function"))?;
                self.two_ways(
                    some,
                    inner,
                    &mut |s| {
                        let p = s.b.opt_get(r);
                        let o = s.owned(Val { v: p, own: false });
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(o))
                    },
                    &mut |s| {
                        let v = s.b.call_ind(f.val.v, &[]);
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "map" | "and_then" | "or_else" => {
                let f = args
                    .first()
                    .copied()
                    .ok_or_else(|| Error::new("missing function"))?;
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
                        // The callback only borrowed the payload: an owned temporary closes it.
                        s.close_owned_temp(recv);
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
            "ok_or" | "ok_or_else" => self.optional_ok_or(out, at, name, recv, args),
            _ => Err(Error::new(format!("unsupported Optional method {name}"))),
        }
    }

    /// `opt.ok_or(cause)` and `opt.ok_or_else(create)`.
    fn optional_ok_or(
        &mut self,
        out: MTy,
        at: ms_syntax::Pos,
        name: &str,
        recv: Val,
        args: Vec<NArg>,
    ) -> Result<Val, Error> {
        let r = recv.v;
        let some = self.b.opt_is_some(r);
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
        let line = at.line;
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
                        s.finish(c.val);
                        p
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
        out: MTy,
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
                            // The default goes unused: an owned resource there closes now.
                            if d.wrapped {
                                s.close_owned_temp(d.val);
                            }
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
                                s.finish(d.val);
                                p
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
                        let o = s.owned(Val { v: r, own: false });
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(o))
                    },
                    &mut |s| {
                        let p = s.b.alt_get(alt, err, 0, r);
                        let v = s.b.call_ind(f.val.v, &[p]);
                        s.close_owned_temp(recv);
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "map_error" => {
                let f = f.ok_or_else(|| Error::new("missing function"))?;
                let TyKind::Alt(oa) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("map_error without Result result"));
                };
                let (out_ok, out_err) = {
                    let cs = &self.b.m.alts[oa.index()].cases;
                    (
                        cs.iter().position(|c| c.name == "ok").unwrap_or(0) as u32,
                        cs.iter().position(|c| c.name == "error").unwrap_or(1) as u32,
                    )
                };
                self.two_ways(
                    is_ok,
                    out,
                    &mut |s| {
                        let p = s.b.alt_get(alt, ok, 0, r);
                        let po = s.owned(Val { v: p, own: false });
                        let v = s.b.alt_new(oa, out_ok, &[po]);
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                    &mut |s| {
                        let p = s.b.alt_get(alt, err, 0, r);
                        let y = s.b.call_ind(f.val.v, &[p]);
                        let v = s.b.alt_new(oa, out_err, &[y]);
                        s.close_owned_temp(recv);
                        s.finish(recv);
                        s.finish(f.val);
                        Ok(Some(v))
                    },
                )
            }
            "get_or_else" => {
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
                        s.close_owned_temp(recv);
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
                        s.close_owned_temp(recv);
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
        let cur = crate::mutation::place_base(&self.hir, e);
        matches!(&cur.kind, ExprKind::Name(_))
            && matches!(self.hir.resolution(cur), Resolution::Local(_))
    }

    pub(crate) fn mutate_any(
        &mut self,
        name: &str,
        old: Value,
        decl: &[ct::Param],
        args: &[NArg],
        copy_result: bool,
        result_ty: MTy,
    ) -> Result<(Value, Option<Val>), Error> {
        // Swapping scalars is two loads and two stores; other elements move through the runtime without a copy.
        let scalar_swap = name == "swap"
            && matches!(self.b.m.types.kind(self.ty_of(old)), TyKind::List(e) if self.b.m.types.is_scalar(*e));
        let runtime_only = !scalar_swap
            && !matches!(
                name,
                "append"
                    | "set"
                    | "replace"
                    | "prepend"
                    | "insert"
                    | "remove"
                    | "pop"
                    | "reverse"
                    | "sort"
            );
        let is_list = matches!(self.b.m.types.kind(self.ty_of(old)), TyKind::List(_));
        // The runtime shifts the tail in place; rebuilding the list from slices copies every element.
        let in_place = matches!(name, "insert" | "remove");
        if !is_list || runtime_only || in_place {
            return self.mutate_rt(name, old, decl, args, copy_result, result_ty);
        }
        let (new, r) = self.mutate_list(name, old, args)?;
        if r.is_none() && copy_result {
            let v = self.owned(Val { v: new, own: false });
            return Ok((new, Some(Val { v, own: true })));
        }
        Ok((new, r))
    }

    /// An owned element for a collection, wrapped when the checker converted it to an optional.
    fn element_value(&mut self, a: &NArg) -> Value {
        let v = self.owned(a.val);
        if a.wrapped { self.b.opt_some(v) } else { v }
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
                let v = self.element_value(&args[0]);
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
                let v = self.element_value(&args[1]);
                Ok((self.b.list_set(old, i, v), None))
            }
            "swap" => {
                let n = self.b.list_len(old);
                let zero = self.b.iconst(0);
                let mut at = [old; 2];
                let mut got = [old; 2];
                for (k, a) in args.iter().enumerate().take(2) {
                    let i = self.borrow(a.val);
                    let neg = self.b.icmp(Cc::Lt, i, zero);
                    let shifted = self.b.binop(Op::IAdd, i, n);
                    let r = self.b.select(neg, shifted, i);
                    self.check_index(3, i, r, n, false);
                    at[k] = r;
                    got[k] = self.b.list_get(old, r);
                }
                let first = self.b.list_set(old, at[0], got[1]);
                Ok((self.b.list_set(first, at[1], got[0]), None))
            }
            "replace" => {
                // The element moves out through a slot and the new value moves in; nothing is copied.
                let idx = self.borrow(args[0].val);
                let v = self.element_value(&args[1]);
                let list = self.put_slot(old);
                let incoming = self.put_slot(v);
                let outgoing = self
                    .b
                    .emit(Op::Slot, &[], ms_mir::ir::Imm::Ty(elem), Some(MTy::PTR))
                    .expect("slot");
                self.call_runtime(
                    "msrt_list_replace",
                    &[list, d, idx, incoming, outgoing],
                    MTy::UNIT,
                )?;
                let new = self.take_slot(list, lt);
                let old_element = self.take_slot(outgoing, elem);
                Ok((
                    new,
                    Some(Val {
                        v: old_element,
                        own: true,
                    }),
                ))
            }
            "prepend" | "insert" | "remove" => {
                let n = self.b.list_len(old);
                let (idx, item) = match name {
                    "prepend" => (self.b.iconst(0), Some(&args[0])),
                    "insert" => (self.borrow(args[0].val), Some(&args[1])),
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
                    let xo = self.element_value(x);
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
                let placeholder = self.b.use_var(res);
                self.drop_value(placeholder);
                self.b.def_var(res, some);
                let rest = self.b.list_drop_last(cur);
                self.b.def_var(acc, rest);
                self.b.br(join, &[]);
                self.b.seal_block(join);
                self.b.switch_to(join);
                let r = self.b.use_var(res);
                let l = self.b.use_var(acc);
                Ok((l, Some(Val { v: r, own: true })))
            }
            "sort" => {
                let f = args
                    .iter()
                    .find(|a| self.is_fn(a.val.v))
                    .ok_or_else(|| Error::new("sort without comparator"))?;
                let ft = self.ty_of(f.val.v);
                let fvar = self.fresh_var(ft);
                let fo = self.owned(f.val);
                self.b.def_var(fvar, fo);
                let var = self.fresh_var(lt);
                self.b.def_var(var, old);
                let r = self.list_sorted(var, fvar, elem)?;
                let o = self.b.use_var(var);
                self.drop_value(o);
                self.release_source(fvar, true);
                Ok((r.v, None))
            }
            "reverse" => {
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

    /// Runs `body(i)` for `i` in `from..n`; `from` and `n` are `Int` values.
    pub(crate) fn counted_loop(
        &mut self,
        from: Value,
        n: Value,
        body: &mut dyn FnMut(&mut Self, Value) -> Result<(), Error>,
    ) -> Result<(), Error> {
        let idx = self.b.declare_var(MTy::INT, Mode::Borrow);
        self.b.def_var(idx, from);
        let (head, step, exit) = (self.b.new_block(), self.b.new_block(), self.b.new_block());
        self.b.br(head, &[]);
        self.b.switch_to(head);
        let i = self.b.use_var(idx);
        let more = self.b.icmp(ms_mir::ir::Cc::Lt, i, n);
        self.b.br_if(more, step, &[], exit, &[]);
        self.b.seal_block(step);
        self.b.switch_to(step);
        let i = self.b.use_var(idx);
        body(self, i)?;
        let one = self.b.iconst(1);
        let i = self.b.use_var(idx);
        let next = self.b.binop(ms_mir::ir::Op::IAdd, i, one);
        self.b.def_var(idx, next);
        self.b.br(head, &[]);
        self.b.seal_block(head);
        self.b.seal_block(exit);
        self.b.switch_to(exit);
        Ok(())
    }

    /// Visits each element with `body(index, element)`; a returned condition leaves the loop when true.
    pub(crate) fn each_element(
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
            "partition" => {
                let TyKind::Rec(rid) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("partition without a record result"));
                };
                let lt = self.b.m.records[rid.index()].fields[0].1;
                let zero = self.b.iconst(0);
                let (yes, no) = (self.fresh_var(lt), self.fresh_var(lt));
                for v in [yes, no] {
                    let first = self.b.list_new(elem, zero);
                    self.b.def_var(v, first);
                }
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let (hit, miss, join) = (s.b.new_block(), s.b.new_block(), s.b.new_block());
                    s.b.br_if(r, hit, &[], miss, &[]);
                    s.b.seal_block(hit);
                    s.b.seal_block(miss);
                    for (blk, acc) in [(hit, yes), (miss, no)] {
                        s.b.switch_to(blk);
                        let xo = s.owned(Val { v: x, own: false });
                        let cur = s.b.use_var(acc);
                        let next = s.b.list_push(cur, xo);
                        s.b.def_var(acc, next);
                        s.b.br(join, &[]);
                    }
                    s.b.seal_block(join);
                    s.b.switch_to(join);
                    Ok(None)
                })?;
                let (a, b) = (self.b.use_var(yes), self.b.use_var(no));
                let rec = self.b.rec_new(rid, &[a, b]);
                Ok(Val { v: rec, own: true })
            }
            "flat_map" => {
                let TyKind::List(res_elem) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("flat_map without list result"));
                };
                let zero = self.b.iconst(0);
                let first = self.b.list_new(res_elem, zero);
                let acc = self.fresh_var(out);
                self.b.def_var(acc, first);
                self.each_element(lv, &mut |s, _, x| {
                    let r = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let rt = s.ty_of(r);
                    let rv = s.fresh_var(rt);
                    s.b.def_var(rv, r);
                    s.each_element(rv, &mut |s, _, y| {
                        let yo = s.owned(Val { v: y, own: false });
                        let cur = s.b.use_var(acc);
                        let next = s.b.list_push(cur, yo);
                        s.b.def_var(acc, next);
                        Ok(None)
                    })?;
                    let done = s.b.use_var(rv);
                    s.drop_value(done);
                    Ok(None)
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: true,
                })
            }
            "group_by" => {
                let TyKind::Obj(_, parts) = self.b.m.types.kind(out).clone() else {
                    return Err(Error::new("group_by without a map result"));
                };
                let group_ty = parts[1];
                let first = self.map_new(out)?;
                let acc = self.fresh_var(out);
                self.b.def_var(acc, first);
                self.each_element(lv, &mut |s, _, x| {
                    let k = {
                        let f = s.b.use_var(fvar);
                        s.b.call_ind(f, &[x])
                    };
                    let (kd, vd) = s.map_descs(out)?;
                    let vd = vd.ok_or_else(|| Error::new("group_by without a value type"))?;
                    // The lookup only reads the key, so it lends the key itself.
                    let kslot = s.lend_slot(k);
                    let m = s.b.use_var(acc);
                    let sym = s
                        .word_map_symbol("msrt_map_get_ptr", out)
                        .unwrap_or("msrt_map_get_ptr");
                    let found = s.call_runtime(sym, &[m, kd, vd, kslot], MTy::PTR)?;
                    let missing =
                        s.b.emit(
                            ms_mir::ir::Op::PtrIsNull,
                            &[found],
                            ms_mir::ir::Imm::None,
                            Some(MTy::BOOL),
                        )
                        .expect("is_null");
                    let TyKind::List(group_elem) = s.b.m.types.kind(group_ty).clone() else {
                        return Err(Error::new("group_by without list groups"));
                    };
                    // A present group is taken out of its entry, grown and put back where it
                    // lies, so a bucket is never copied; an absent one starts as `[x]`.
                    let cur = s.b.use_var(acc);
                    let next = s
                        .two_ways(
                            missing,
                            out,
                            &mut |s| {
                                let empty = s.b.list_lit(group_elem, &[]);
                                let xo = s.owned(Val { v: x, own: false });
                                let grown = s.b.list_push(empty, xo);
                                let next = s.map_insert(cur, k, grown)?;
                                Ok(Some(next))
                            },
                            &mut |s| {
                                let taken =
                                    s.b.emit(
                                        ms_mir::ir::Op::Take,
                                        &[found],
                                        ms_mir::ir::Imm::Ty(group_ty),
                                        Some(group_ty),
                                    )
                                    .expect("take");
                                let xo = s.owned(Val { v: x, own: false });
                                let grown = s.b.list_push(taken, xo);
                                s.b.emit(
                                    ms_mir::ir::Op::Put,
                                    &[found, grown],
                                    ms_mir::ir::Imm::None,
                                    None,
                                );
                                s.drop_value(k);
                                Ok(Some(cur))
                            },
                        )?
                        .v;
                    s.b.def_var(acc, next);
                    Ok(None)
                })?;
                Ok(Val {
                    v: self.b.use_var(acc),
                    own: true,
                })
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
            "any" | "all" => {
                let some = name == "any";
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
            "find" | "find_index" | "find_last_index" => {
                let by_index = name != "find";
                // The last match wins: keep scanning past hits.
                let last = name == "find_last_index";
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
                    let old = s.b.use_var(acc);
                    s.drop_value(old);
                    s.b.def_var(acc, some);
                    s.b.br(miss, &[]);
                    s.b.switch_to(miss);
                    // The last hit wins, so `find_last_index` visits every element.
                    Ok((!last).then_some(r))
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

    /// Appends the declared default of every omitted parameter that has one (`none` aside),
    /// evaluated in the declaring module.
    pub(crate) fn fill_native_defaults(
        &mut self,
        module: ct::Name,
        func: Option<&ms_syntax::ast::Func>,
        params: &[ct::Param],
        args: &mut Vec<NArg>,
    ) -> Result<(), Error> {
        let Some(f) = func else {
            return Ok(());
        };
        for (i, p) in params.iter().enumerate() {
            if args.iter().any(|a| a.name == p.name) {
                continue;
            }
            let Some(d) = f.params.get(i).and_then(|q| q.default.as_ref()) else {
                continue;
            };
            if matches!(&d.kind, ExprKind::Name(n) if n.as_str() == "none") {
                continue;
            }
            // Bundled declarations carry no checked facts: literal defaults are built directly,
            // anything else through the declaring module when it was checked.
            let r = match &d.kind {
                ExprKind::Bool(b) => Ok(Val {
                    v: self.b.bconst(*b),
                    own: false,
                }),
                ExprKind::Number(t) if p.ty.id.as_str() == "Int" => {
                    match ms_syntax::number::canonical(t.as_str()).parse::<i64>() {
                        Ok(n) => Ok(Val {
                            v: self.b.iconst(n),
                            own: false,
                        }),
                        Err(_) => continue,
                    }
                }
                ExprKind::Text(parts) if parts.iter().all(|t| matches!(t, TextPart::Lit(_))) => {
                    let text: String = parts
                        .iter()
                        .map(|t| match t {
                            TextPart::Lit(s) => s.as_ref(),
                            TextPart::Interp(_) => "",
                        })
                        .collect();
                    Ok(self.lit(&text))
                }
                ExprKind::Call { .. } | ExprKind::Member { .. }
                    if self.cx.module(module).is_err() =>
                {
                    match self.literal_default(d, &p.ty)? {
                        Some(v) => Ok(v),
                        None => continue,
                    }
                }
                _ => {
                    let Ok(hir) = self.cx.module(module) else {
                        continue;
                    };
                    let saved_hir = std::mem::replace(&mut self.hir, hir);
                    let saved_file = self.file;
                    self.file = self.b.m.add_file(module.as_str());
                    // A default reports its own position, not the caller statement\'s.
                    let saved_stmt = self.stmt_pos.take();
                    let r = self.expr(d);
                    self.stmt_pos = saved_stmt;
                    self.hir = saved_hir;
                    self.file = saved_file;
                    r
                }
            };
            let mut val = r?;
            if p.ty.is_std("Optional") {
                let o = self.owned(val);
                val = Val {
                    v: self.b.opt_some(o),
                    own: true,
                };
            }
            args.push(NArg {
                name: p.name,
                val,
                wrapped: false,
            });
        }
        Ok(())
    }

    /// The written arguments of a native call in order; `wrapped` marks values meant for an `Optional` parameter.
    pub(crate) fn native_args(&mut self, view: &CallView<'_>) -> Result<Vec<NArg>, Error> {
        let mut out = Vec::new();
        let mut read_at = Vec::new();
        for (n, a) in view.arguments.iter().enumerate() {
            let at = self.b.current();
            let val = self.expr(a.expr)?;
            if self.dead {
                break;
            }
            read_at.push((a.expr, at));
            let later_try = view.arguments[n + 1..]
                .iter()
                .any(|l| crate::mutation::has_try(l.expr));
            let val = if later_try { self.hold_temp(val) } else { val };
            out.push(NArg {
                name: a.slot.name,
                val,
                wrapped: a.wrap_optional.is_some(),
            });
        }
        for (arg, (expr, at)) in out.iter_mut().zip(read_at) {
            arg.val = self.refresh(expr, arg.val, at)?;
        }
        // Written order decides evaluation; callers index by declared parameter position, so
        // `set(value: 8, 0)` must hand them the index before the value.
        let declared: Vec<ct::Name> = match &view.target {
            Resolution::Method(m) => m.ty.params.iter().map(|p| p.name).collect(),
            Resolution::Function(sym) => sym
                .ty
                .borrow()
                .as_ref()
                .map(|t| t.params.iter().map(|p| p.name).collect())
                .unwrap_or_default(),
            _ => Vec::new(),
        };
        out.sort_by_key(|a| {
            declared
                .iter()
                .position(|n| *n == a.name)
                .unwrap_or(usize::MAX)
        });
        Ok(out)
    }

    /// `(present, value)` operands of an optional `Int` argument for runtime calls.
    pub(crate) fn optional_int(&mut self, arg: Option<NArg>) -> Result<(Value, Value), Error> {
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
        let scope = self.glue_scope(t);
        self.cx.ensure_glue(self.b.m, t, scope);
        self.b
            .emit(
                ms_mir::ir::Op::TypeDesc,
                &[],
                ms_mir::ir::Imm::Ty(t.scoped(scope)),
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
        // The eager default is unused on this path.
        self.finish(default.val);
        self.b.def_var(out, xo);
        self.b.br(join, &[]);
        self.b.switch_to(miss);
        if default.wrapped {
            let d = self.owned(default.val);
            self.b.def_var(out, d);
            self.b.br(join, &[]);
        } else {
            // An omitted `Optional` default faults like a plain read.
            let has = self.b.opt_is_some(default.val.v);
            let (give, fault) = (self.b.new_block(), self.b.new_block());
            self.b.br_if(has, give, &[], fault, &[]);
            self.b.seal_block(give);
            self.b.seal_block(fault);
            self.b.switch_to(give);
            let inner = self.b.opt_get(default.val.v);
            let d = self.owned(Val {
                v: inner,
                own: false,
            });
            self.finish(default.val);
            self.b.def_var(out, d);
            self.b.br(join, &[]);
            self.b.switch_to(fault);
            let x = self.b.list_get(l, idx);
            let xo = self.owned(Val { v: x, own: false });
            self.finish(default.val);
            self.b.def_var(out, xo);
            self.b.br(join, &[]);
        }
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
    let which = b.iconst(i64::from(stderr));
    if name == "close" {
        let ext = runtime_fn(b.m, "msrt_io_close", &[MTy::INT], MTy::UNIT);
        b.call_rt(ext, &[which]);
    }
    let alt = match b.m.types.kind(ret).clone() {
        TyKind::Alt(a) => Some(a),
        _ => None,
    };
    let case = |m: &ms_mir::ir::Module, a: ms_mir::types::AltId, n: &str| {
        m.alts[a.index()]
            .cases
            .iter()
            .position(|c| c.name == n)
            .map(|i| i as u32)
    };
    if name == "write" || name == "write_bytes" {
        let (sym, arg) = match (name == "write", stderr) {
            (true, true) => ("msrt_io_write_stderr", MTy::STR),
            (true, false) => ("msrt_io_write_stdout", MTy::STR),
            (false, true) => ("msrt_io_write_bytes_stderr", MTy::BYTES),
            (false, false) => ("msrt_io_write_bytes_stdout", MTy::BYTES),
        };
        let ext = runtime_fn(b.m, sym, &[arg], MTy::UNIT);
        b.call_rt(ext, &[args[1]]);
    } else if name == "flush" {
        let ext = runtime_fn(b.m, "msrt_io_flush", &[], MTy::UNIT);
        b.call_rt(ext, &[]);
    }
    match alt {
        Some(a) => {
            let ok = case(b.m, a, "ok").unwrap_or(0);
            let u = b.unit();
            let r = b.alt_new(a, ok, &[u]);
            b.ret(Some(r));
        }
        None => {
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

/// The runtime symbol of a `HashAlgorithm` operation, by native identity.
fn hash_algorithm_symbol(native: &str) -> Option<&'static str> {
    match native {
        "crypto/hash_algorithm_digest" => Some("msrt_crypto_digest"),
        "crypto/hash_algorithm_hmac" => Some("msrt_crypto_hmac"),
        "derive_key" | "crypto/hash_algorithm_derive_key" => Some("msrt_crypto_derive_key"),
        "hkdf" | "crypto/hash_algorithm_hkdf" => Some("msrt_crypto_hkdf"),
        "crypto/hash_algorithm_hasher" => Some("msrt_crypto_hasher_new"),
        "crypto/hash_algorithm_hmac_hasher" => Some("msrt_crypto_hmac_hasher_new"),
        _ => None,
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
        match (n.as_str(), m.name()?.as_str()) {
            ("Map", "entries") => Some(Walk::Entries),
            ("Map", "values") => Some(Walk::Values),
            ("Map", "keys") | ("Set", "values") => Some(Walk::Keys),
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
        let is_map =
            matches!(self.b.m.types.kind(self.ty_of(recv)), TyKind::Obj(n, _) if n == "Map");
        match m.name()?.as_str() {
            "keys" if is_map => Some("msrt_map_keys_view"),
            "values" if is_map => Some("msrt_map_values_view"),
            _ => None,
        }
    }
}
