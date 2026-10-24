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
/// Methods of format enums: native, runtime symbol, the runtime's format parameter, and whether
/// the runtime wants the case index (else the lowercase case name).
const FORMAT_METHODS: &[(&str, &str, &str, bool)] = &[
    (
        "string/form_normalize",
        "msrt_string_normalize_kind",
        "kind",
        true,
    ),
    ("archive/format_pack", "msrt_archive_pack", "format", false),
    (
        "archive/format_unpack",
        "msrt_archive_unpack",
        "format",
        false,
    ),
    (
        "archive/format_compress",
        "msrt_compress_compress",
        "format",
        false,
    ),
    (
        "archive/format_decompress",
        "msrt_compress_decompress",
        "format",
        false,
    ),
];

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
        "map"
            | "filter"
            | "flat_map"
            | "group_by"
            | "count"
            | "some"
            | "every"
            | "for_each"
            | "find"
            | "find_index"
            | "find_last_index"
    )
}

/// The `module/name` of natives that bindings override with a bare name.
/// The host-rule path functions that `fs` absorbed from the former `path` module.
const PATH_FUNCTIONS: [&str; 15] = [
    "basename",
    "dirname",
    "extension",
    "is_absolute",
    "join",
    "normalize",
    "relative",
    "basename_without",
    "resolve",
    "parse",
    "format",
    "separator",
    "delimiter",
    "to_namespaced_path",
    "matches_glob",
];

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
        sym: &ct::SymRef,
    ) -> Result<Val, Error> {
        if let Some(symbol) = native.strip_prefix("extern:") {
            return self.extern_call(e, view, symbol, params);
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
            "random/secure_int" | "random/uuid_v4" | "random/float" | "random/shuffle"
            | "random/choice" => self.random_native(e, view, native),
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
            "collections/map_from_entries"
            | "crypto/sha256"
            | "crypto/sha384"
            | "crypto/sha512"
            | "crypto/derive_key" => {
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
            "time/duration" => {
                // A `Duration` is its count of nanoseconds.
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::INT));
                }
                let n = args
                    .first()
                    .ok_or_else(|| Error::new("duration without nanoseconds"))?;
                Ok(Val {
                    v: self.borrow(n.val),
                    own: false,
                })
            }
            "sleep" => {
                let args = self.native_args(view)?;
                if self.dead {
                    return Ok(self.dummy(MTy::UNIT));
                }
                let d = args
                    .first()
                    .ok_or_else(|| Error::new("sleep without a duration"))?;
                let d = self.borrow(d.val);
                self.at(e.pos);
                self.call_runtime("msstd_time_sleep", &[d], MTy::UNIT)?;
                Ok(self.dummy(MTy::UNIT))
            }
            "math/min" => self.math_extreme(view, false),
            "math/max" => self.math_extreme(view, true),
            "math/min_of" => self.math_extreme_of(e, view, false),
            "math/max_of" => self.math_extreme_of(e, view, true),
            "io/read_all" => self.stream_native(e, view, crate::streamloop::Loop::ReadAll),
            "io/copy" => self.stream_native(e, view, crate::streamloop::Loop::Copy),
            other
                if crate::natiface::HANDLE_FUNCTIONS
                    .iter()
                    .any(|f| f.0 == other) =>
            {
                let &(_, module, make, constant) = crate::natiface::HANDLE_FUNCTIONS
                    .iter()
                    .find(|f| f.0 == other)
                    .expect("listed");
                let (ity, want) = (self.ety(e), self.emty(e)?);
                self.handle_interface(&ity, want, module, make, constant)
            }
            other if other.starts_with("testing/") => {
                self.testing_native(e, view, &other["testing/".len()..])
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
                if other
                    .strip_prefix("fs/")
                    .is_some_and(|name| PATH_FUNCTIONS.contains(&name))
                {
                    // The host-rule functions share the interface's entry points; the leading
                    // `windows` flag selects the host's rules.
                    let name = ct::n("windows");
                    let v = self.b.bconst(cfg!(windows));
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
                    return self.native_call(other, &decl, &args, result);
                }
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
                | "math/max_of"
                | "math/min_of"
                | "time/duration"
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
        if matches!(native, "math/max_of" | "math/min_of") {
            return self.extreme_of(native == "math/max_of", args, result);
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
        if native == "time/duration" {
            return Ok(Val {
                v: self.borrow(args[0].val),
                own: false,
            });
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

    /// `max_of(values)` / `min_of(values)`: the first greatest (least) element, or `none`.
    fn extreme_of(&mut self, max: bool, args: &[NArg], result: MTy) -> Result<Val, Error> {
        use ms_mir::ir::Cc;
        // The list lives in a variable so the loop and the branches may read it.
        let list = self.borrow(args[0].val);
        let lt = self.ty_of(list);
        let lvar = self.fresh_var(lt);
        let held_list = self.owned(Val {
            v: list,
            own: false,
        });
        self.b.def_var(lvar, held_list);
        let n = self.b.list_len(list);
        let (zero, one) = (self.b.iconst(0), self.b.iconst(1));
        let best = self.b.declare_var(MTy::INT, Mode::Borrow);
        self.b.def_var(best, zero);
        self.counted_loop(one, n, &mut |s, iv| {
            let bv = s.b.use_var(best);
            let l = s.b.use_var(lvar);
            let cur = s.b.list_get(l, iv);
            let held = s.b.list_get(l, bv);
            let above = if max {
                s.strictly_above(cur, held)?
            } else {
                s.strictly_above(held, cur)?
            };
            let pick = s.b.select(above, iv, bv);
            s.b.def_var(best, pick);
            Ok(())
        })?;
        let empty = self.b.icmp(Cc::Eq, n, zero);
        let TyKind::Opt(elem) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("max_of and min_of return an Optional"));
        };
        let out = self.two_ways(
            empty,
            result,
            &mut |s| {
                let v = s.b.opt_none(result);
                Ok(Some(s.owned(Val { v, own: false })))
            },
            &mut |s| {
                let bv = s.b.use_var(best);
                let l = s.b.use_var(lvar);
                let item = s.b.list_get(l, bv);
                let o = s.owned(Val {
                    v: item,
                    own: false,
                });
                let _ = elem;
                Ok(Some(s.b.opt_some(o)))
            },
        )?;
        self.release_source(lvar, true);
        Ok(out)
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
        if native == "time/duration_nanoseconds" {
            // A `Duration` is its count of nanoseconds.
            return Ok(Val {
                v: self.borrow(recv),
                own: false,
            });
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
            (TyKind::Obj(n, _), "entries") if n == "Set" => {
                let result = self.emty(e)?;
                self.set_entries(recv, result)
            }
            (TyKind::List(_), "list_keys") => {
                let result = self.emty(e)?;
                let r = self.borrow(recv);
                let n = self.b.list_len(r);
                let acc = self.fresh_var(result);
                let first = self.b.list_new(MTy::INT, n);
                self.b.def_var(acc, first);
                let (lv, hidden) = self.list_source(Some(recv_expr), recv)?;
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
            (TyKind::List(_), "list_entries") => {
                let result = self.emty(e)?;
                self.list_entries(recv_expr, recv, result)
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
                let (lv, hidden) = self.list_source(Some(recv_expr), recv)?;
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
            (TyKind::Rec(rid), "unix_seconds" | "nanoseconds")
                if self.b.m.records[rid.index()].name == "Timestamp" =>
            {
                // A timestamp is its two words; these read them.
                let x = self.borrow(recv);
                let field = u32::from(name == "nanoseconds");
                let v = self.b.rec_get(rid, field, x);
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
                let out = self.emty(e)?;
                self.optional_method(out, e.pos, name, recv, inner, args)
            }
            (TyKind::Alt(a), "get" | "err" | "or_else" | "map" | "and_then" | "to_optional") => {
                let out = self.emty(e)?;
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
                let (lv, hidden) = self.list_source(Some(recv_expr), recv)?;
                let r = self.list_sorted(lv, fvar, elem);
                self.release_source(lv, hidden);
                self.release_source(fvar, true);
                r
            }
            _ if crate::iterate::handles(self.b.m, rty, name) => {
                let out = self.emty(e)?;
                self.iterate_method(out, name, Some(recv_expr), recv, args)
            }
            (TyKind::List(_), _) if is_higher_order(name) => {
                let out = self.emty(e)?;
                self.list_higher(name, out, Some(recv_expr), recv, args)
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
        let r = self.borrow(recv);
        let tag = self.b.alt_tag(r);
        let k = self.b.iconst(case as i64);
        let v = self.b.icmp(ms_mir::ir::Cc::Eq, tag, k);
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
        if let Some(v) = self.time_field(m, recv)? {
            return Ok(v);
        }
        let rty = self.ty_of(recv.v);
        let name = m.name().map(|n| n.to_string()).unwrap_or_default();
        if let Some(&(_, sym, param, as_text)) = FORMAT_METHODS
            .iter()
            .find(|(n, ..)| *n == m.native.as_str())
        {
            return self.format_method(result, m, recv, args.to_vec(), (sym, param, as_text));
        }
        if crate::sharedbuilder::builder_kind(&m.receiver).is_some() {
            let handle = self.borrow(recv);
            return self.builder_call(&name, handle, &m.ty.params, args, result);
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
        if let (TyKind::Alt(a), "get" | "err" | "or_else" | "map" | "and_then" | "to_optional") =
            (self.b.m.types.kind(rty).clone(), name.as_str())
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

    /// `Timestamp` and `Duration` accessors that read the representation directly.
    fn time_field(&mut self, m: &ct::MethodRef, recv: Val) -> Result<Option<Val>, Error> {
        let name = m.name().map(|n| n.to_string()).unwrap_or_default();
        if m.receiver.is_std("Duration") && name == "to_nanoseconds" {
            return Ok(Some(Val {
                v: self.borrow(recv),
                own: false,
            }));
        }
        if m.receiver.is_std("ClientResponse") && name == "metadata" {
            let TyKind::Rec(rid) = self.b.m.types.kind(self.ty_of(recv.v)).clone() else {
                return Err(Error::new("ClientResponse is not a record"));
            };
            let r = self.borrow(recv);
            let v = self.b.rec_get(rid, 0, r);
            return Ok(Some(Val { v, own: false }));
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
        if name == "add"
            && let Some(done) = self.fused_update(e, view, m, recv_expr)?
        {
            return Ok(done);
        }
        if let Some(done) = self.lent_key_add(e, view, m, recv_expr, name)? {
            return Ok(done);
        }
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
        let runtime_only = !matches!(
            name,
            "append" | "set" | "prepend" | "insert" | "remove" | "pop" | "reverse_in_place"
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
                    let group = s.two_ways(
                        missing,
                        group_ty,
                        &mut |s| Ok(Some(s.b.list_lit(group_elem, &[]))),
                        &mut |s| {
                            let at =
                                s.b.emit(
                                    ms_mir::ir::Op::Load,
                                    &[found],
                                    ms_mir::ir::Imm::Ty(group_ty),
                                    Some(group_ty),
                                )
                                .expect("load");
                            Ok(Some(s.owned(Val { v: at, own: false })))
                        },
                    )?;
                    let xo = s.owned(Val { v: x, own: false });
                    let grown = s.b.list_push(group.v, xo);
                    let cur = s.b.use_var(acc);
                    let next = s.map_insert(cur, k, grown)?;
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
                ExprKind::Number(t) if p.ty.id.as_str() == "Int" => match t.as_str().parse::<i64>()
                {
                    Ok(n) => Ok(Val {
                        v: self.b.iconst(n),
                        own: false,
                    }),
                    Err(_) => continue,
                },
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
                ExprKind::Call { .. } if self.cx.module(module).is_err() => {
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
    if matches!(name, "write" | "write_bytes")
        && let Some(a) = alt
        && let Some(error) = case(b.m, a, "error")
        && let TyKind::Alt(io) =
            b.m.types
                .kind(b.m.alts[a.index()].cases[error as usize].fields[0].1)
                .clone()
        && let Some(closed) = case(b.m, io, "Closed")
    {
        // A closed stream reports `Closed` instead of writing.
        let is_closed = runtime_fn(b.m, "msrt_io_closed", &[MTy::INT], MTy::BOOL);
        let shut = b.call_rt(is_closed, &[which]);
        let (fail, go) = (b.new_block(), b.new_block());
        b.br_if(shut, fail, &[], go, &[]);
        b.seal_block(fail);
        b.seal_block(go);
        b.switch_to(fail);
        let cause = b.alt_new(io, closed, &[]);
        let r = b.alt_new(a, error, &[cause]);
        b.ret(Some(r));
        b.switch_to(go);
    }
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
