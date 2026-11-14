//! Direct emission of glue functions as LLVM IR (`proposals/mir-to-llvm-direct.md`, stage 4).
//!
//! Glue (drop, clone, slot and block helpers) has no MIR: the Cranelift lowering builds it from
//! the type. This module writes the same bodies straight through the typed builder for the types
//! it covers (strings, lists, plain types, optionals); every other glue keeps the old path.

use crate::Glue;
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use crate::mir_llvm::Emitted;
use crate::state::Gen;
use ms_mir::layout::{AltRepr, Layouts, Leaf, mem_layout};
use ms_mir::types::{Ty, TyKind};
use ms_rt_abi::STR_INLINE;
use ms_rt_abi::symbols::{DEEP_DROP_HEADROOM, STACK_LIMIT_CELL, STACK_REGION};

pub mod closure;

type Vs = Vec<Val>;

fn reg(l: Leaf) -> LTy {
    match l {
        Leaf::I64 | Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => LTy::I64,
        Leaf::F64 => LTy::F64,
        Leaf::F32 => LTy::F32,
        Leaf::I8 => LTy::I8,
    }
}

fn mem(l: Leaf) -> LTy {
    match l {
        Leaf::N8 | Leaf::U8 | Leaf::I8 => LTy::I8,
        Leaf::N16 | Leaf::U16 => LTy::I16,
        Leaf::N32 | Leaf::U32 => LTy::I32,
        Leaf::I64 => LTy::I64,
        Leaf::F64 => LTy::F64,
        Leaf::F32 => LTy::F32,
    }
}

fn attr(l: Leaf) -> &'static str {
    if l == Leaf::I8 { " zeroext" } else { "" }
}

/// Whether the body of the glue `kind` for `ty` can be written here.
pub fn supports(g: &Gen, kind: Glue, ty: Ty) -> bool {
    let m = g.m;
    match kind {
        Glue::SlotDrop | Glue::SlotCopy | Glue::BlockDrop | Glue::BlockClone => true,
        Glue::CleanupThunk(_) => true,
        k if closure::is_closure(k) => true,
        Glue::Drop => match m.types.kind(ty) {
            TyKind::Bytes | TyKind::List(_) => true,
            TyKind::Type(_) => true,
            TyKind::Opt(inner) => {
                g.lay.opt_is_boxed(*inner)
                    || g.lay.is_str_like(ty)
                    || !g.lay.opt_is_nullable(*inner)
            }
            _ => true,
        },
        Glue::Clone => true,
        _ => false,
    }
}

/// How a value of one type is cloned or dropped.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum OwnKind {
    /// Plain data: the copy is the value and there is nothing to drop.
    Identity,
    /// A string: static and inline ones copy bitwise and own nothing; the others go through
    /// the runtime.
    Str,
    /// A closure or an object with a clone entry in its header.
    Obj,
    /// The `Clone` or `Drop` glue function of the type.
    Glue,
}

/// Whether a value of `ty` is a pointer to an object with a header (a closure or a native
/// object other than a map or set), or an optional of one.
pub fn is_obj_like(lay: &Layouts, ty: Ty) -> bool {
    match lay.m.types.kind(ty) {
        TyKind::Fn(..) => true,
        TyKind::Obj(n, _) => !n.is_map_or_set(),
        TyKind::Opt(inner) => lay.opt_is_nullable(*inner) && !lay.opt_is_boxed(*inner),
        _ => false,
    }
}

pub fn own_kind(lay: &Layouts, ty: Ty) -> OwnKind {
    if !lay.m.needs_drop(ty) {
        OwnKind::Identity
    } else if lay.is_str_like(ty) {
        OwnKind::Str
    } else if is_obj_like(lay, ty) {
        OwnKind::Obj
    } else {
        OwnKind::Glue
    }
}

/// Clones the string `vs` (pointer, tagged capacity) from the current block, which is `pre`:
/// a static (`10`) or inline (`01`) string is the same value, any other is copied by the
/// runtime in block `dup`. Ends in block `join` with the two leaves as phis, named `out` when
/// given.
pub fn clone_str(
    b: &mut FnBuilder,
    decls: &mut Vec<(String, String)>,
    (pre, dup, join): (&str, &str, &str),
    vs: &[Val],
    out: Option<&[Val]>,
) -> Vs {
    // A literal's length word is a constant whose tag says it is shared: the clone is the
    // operand. The blocks stay (their labels are planned) but hold no test or copy.
    let shared_const = vs[1]
        .text
        .parse::<i64>()
        .is_ok_and(|w| matches!((w as u64) >> 62, 1 | 2));
    if shared_const {
        b.br(join);
        b.label(join);
        return (0..2)
            .map(|i| {
                let p = match out {
                    Some(o) => o[i].clone(),
                    None => b.reserve(LTy::I64),
                };
                b.phi(&p, &[(vs[i].clone(), pre.to_string())]);
                p
            })
            .collect();
    }
    decls.push((
        "msrt_str_copy".into(),
        "declare void @\"msrt_str_copy\"(i64, i64, i64) nounwind".into(),
    ));
    let tag = b.bin(Bin::LShr, &vs[1], &Val::int(62));
    let tag = b.bin(Bin::Sub, &tag, &Val::int(1));
    let shared = b.icmp("ult", &tag, &Val::int(2));
    b.cond_br(&shared, join, dup);
    b.label(dup);
    let slot = b.alloca(&LTy::Array(Box::new(LTy::I64), 2));
    let at = b.ptrtoint(&slot);
    b.call(
        &LTy::Void,
        "",
        "msrt_str_copy",
        &[(vs[0].clone(), ""), (vs[1].clone(), ""), (at, "")],
    );
    let c0 = b.load(&LTy::I64, &slot, 8);
    let hi = b.gep_bytes(&slot, 8);
    let c1 = b.load(&LTy::I64, &hi, 8);
    b.br(join);
    b.label(join);
    [c0, c1]
        .into_iter()
        .enumerate()
        .map(|(i, c)| {
            let p = match out {
                Some(o) => o[i].clone(),
                None => b.reserve(LTy::I64),
            };
            b.phi(
                &p,
                &[(vs[i].clone(), pre.to_string()), (c, dup.to_string())],
            );
            p
        })
        .collect()
}

// ---- native calling convention ---------------------------------------------------------------
//
// Glue is internal to the LLVM module. Its native entry `@"sym.n"` takes a value of at most 16
// bytes in registers and a larger one by pointer: a moved value as `ptr nonnull nocapture noalias`,
// a borrowed one as `ptr nonnull readonly nocapture`, a result as a hidden `sret` first parameter.
// `@"sym"` keeps the leaf signature the runtime, descriptors and translated code call, and
// forwards to the native entry, so direct callers inline the body. (`proposals/mir-to-llvm-direct.md`,
// "Calling convention"; this is the one place that knows it for glue.)

/// The native entry's symbol for glue `sym`.
pub fn native(sym: &str) -> String {
    format!("{sym}.n")
}

/// The symbol a direct caller calls for glue `sym` of `kind` over `ty`: the native entry when it
/// is emitted directly, else the leaf symbol of the Cranelift lowering.
pub fn target(g: &Gen, kind: Glue, ty: Ty, sym: String) -> String {
    if supports(g, kind, ty) {
        native(&sym)
    } else {
        sym
    }
}

/// The glue symbol a native entry belongs to, or `None` for a leaf symbol.
pub fn unnative(sym: &str) -> Option<&str> {
    sym.strip_suffix(".n")
}

/// The type of a value of `leaves` in memory: a literal struct of the leaves' memory types, laid
/// out like [`mem_layout`].
fn slot_ty(leaves: &[Leaf]) -> LTy {
    LTy::Tuple(leaves.iter().map(|l| mem(*l)).collect())
}

/// Whether a value of `leaves` travels by pointer.
fn indirect(leaves: &[Leaf]) -> bool {
    mem_layout(leaves).size > 16
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    /// Read-only for the call.
    Borrow,
    /// Owned by the callee, which may drop and overwrite it.
    Move,
}

/// Attributes (leading space) of a pointer to a value of `leaves`.
fn ptr_attrs(mode: Mode, leaves: &[Leaf]) -> String {
    let lay = mem_layout(leaves);
    let own = match mode {
        Mode::Borrow => "readonly nocapture",
        Mode::Move => "nocapture noalias",
    };
    let deref = if lay.size > 0 {
        format!(" dereferenceable({})", lay.size)
    } else {
        String::new()
    };
    format!(" noundef nonnull {own} align {}{deref}", lay.align)
}

/// The hidden result pointer of a value of `leaves`.
fn sret_attrs(leaves: &[Leaf]) -> String {
    let lay = mem_layout(leaves);
    format!(
        " sret({}) noundef nonnull nocapture noalias align {} dereferenceable({})",
        Types::default().text(&slot_ty(leaves)),
        lay.align,
        lay.size
    )
}

/// A parameter: its type and the attributes after it (leading space).
struct P {
    ty: LTy,
    attrs: String,
}

/// A native signature.
struct Sig {
    params: Vec<P>,
    ret: LTy,
    ret_attr: &'static str,
}

impl Sig {
    fn formals(&self, named: bool) -> String {
        let t = Types::default();
        self.params
            .iter()
            .enumerate()
            .map(|(i, p)| {
                let name = if named {
                    format!(" %a{i}")
                } else {
                    String::new()
                };
                format!("{}{}{name}", t.text(&p.ty), p.attrs)
            })
            .collect::<Vec<_>>()
            .join(", ")
    }

    fn ret_text(&self) -> String {
        format!("{}{}", self.ret_attr, Types::default().text(&self.ret))
    }

    fn declare(&self, sym: &str) -> (String, String) {
        (
            sym.to_string(),
            format!(
                "declare {} @\"{sym}\"({})",
                self.ret_text(),
                self.formals(false)
            ),
        )
    }
}

fn reg_params(leaves: &[Leaf]) -> Vec<P> {
    leaves
        .iter()
        .map(|l| P {
            ty: reg(*l),
            attrs: attr(*l).to_string(),
        })
        .collect()
}

/// The result type of `leaves` in registers: nothing, the leaf, or a pair.
fn reg_ret(leaves: &[Leaf]) -> (LTy, &'static str) {
    match leaves {
        [] => (LTy::Void, ""),
        [l] => (reg(*l), if attr(*l).is_empty() { "" } else { "zeroext " }),
        ls => (LTy::Tuple(ls.iter().map(|l| reg(*l)).collect()), ""),
    }
}

fn drop_sig(leaves: &[Leaf]) -> Sig {
    let params = if indirect(leaves) {
        vec![P {
            ty: LTy::Ptr,
            attrs: ptr_attrs(Mode::Move, leaves),
        }]
    } else {
        reg_params(leaves)
    };
    Sig {
        params,
        ret: LTy::Void,
        ret_attr: "",
    }
}

fn clone_sig(leaves: &[Leaf]) -> Sig {
    if !indirect(leaves) {
        let (ret, ret_attr) = reg_ret(leaves);
        return Sig {
            params: reg_params(leaves),
            ret,
            ret_attr,
        };
    }
    Sig {
        params: vec![
            P {
                ty: LTy::Ptr,
                attrs: sret_attrs(leaves),
            },
            P {
                ty: LTy::Ptr,
                attrs: ptr_attrs(Mode::Borrow, leaves),
            },
        ],
        ret: LTy::Void,
        ret_attr: "",
    }
}

/// The native signature of glue `kind` over a value of `leaves`.
fn native_sig(kind: Glue, leaves: &[Leaf]) -> Sig {
    let ptr = |mode| P {
        ty: LTy::Ptr,
        attrs: ptr_attrs(mode, leaves),
    };
    let void = |params| Sig {
        params,
        ret: LTy::Void,
        ret_attr: "",
    };
    match kind {
        Glue::Drop => drop_sig(leaves),
        Glue::Clone => clone_sig(leaves),
        Glue::SlotDrop | Glue::BlockDrop => void(vec![ptr(Mode::Move)]),
        Glue::SlotCopy => void(vec![
            ptr(Mode::Borrow),
            P {
                ty: LTy::Ptr,
                attrs: format!(
                    " noundef nonnull nocapture noalias writeonly align {}",
                    mem_layout(leaves).align
                ),
            },
        ]),
        Glue::BlockClone => Sig {
            params: vec![ptr(Mode::Borrow)],
            ret: LTy::Ptr,
            ret_attr: "noalias ",
        },
        Glue::CleanupThunk(_) => void(vec![P {
            ty: LTy::Ptr,
            attrs: " noundef nonnull nocapture".into(),
        }]),
        _ => unreachable!("supports rejects other glue"),
    }
}

/// The leaf signature of glue `kind` (what `@"sym"` has).
fn leaf_sig(kind: Glue, leaves: &[Leaf]) -> Sig {
    let word = |n: usize| {
        (0..n)
            .map(|_| P {
                ty: LTy::I64,
                attrs: String::new(),
            })
            .collect::<Vec<_>>()
    };
    let void = |params| Sig {
        params,
        ret: LTy::Void,
        ret_attr: "",
    };
    match kind {
        Glue::Drop => void(reg_params(leaves)),
        Glue::Clone => {
            let (ret, ret_attr) = reg_ret(leaves);
            Sig {
                params: reg_params(leaves),
                ret,
                ret_attr,
            }
        }
        Glue::BlockClone => Sig {
            params: word(1),
            ret: LTy::I64,
            ret_attr: "",
        },
        Glue::SlotCopy => void(word(2)),
        _ => void(word(1)),
    }
}

/// Loads the leaves stored at `p`, a `ptr` to a [`slot_ty`] value. A given name is the one the
/// leaf's final instruction defines.
fn load_leaves(b: &mut FnBuilder, p: &Val, leaves: &[Leaf], names: Option<&[Val]>) -> Vs {
    let ty = slot_ty(leaves);
    let mut out = Vec::new();
    for (k, l) in leaves.iter().enumerate() {
        let at = b.field_ptr(&ty, p, k);
        let packed = !matches!(l, Leaf::I64 | Leaf::F64 | Leaf::F32 | Leaf::I8);
        if !packed && let Some(n) = names {
            b.name_next(&n[k]);
        }
        let v = b.load(&mem(*l), &at, l.size() as u64);
        out.push(match l {
            Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => {
                if let Some(n) = names {
                    b.name_next(&n[k]);
                }
                if matches!(l, Leaf::N8 | Leaf::N16 | Leaf::N32) {
                    b.sext(&v, LTy::I64)
                } else {
                    b.zext(&v, LTy::I64)
                }
            }
            _ => v,
        });
    }
    out
}

/// Stores `vs` as a [`slot_ty`] value at `p`.
fn store_leaves(b: &mut FnBuilder, p: &Val, leaves: &[Leaf], vs: &[Val]) {
    let ty = slot_ty(leaves);
    for (k, l) in leaves.iter().enumerate() {
        let at = b.field_ptr(&ty, p, k);
        let v = match l {
            Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => {
                b.trunc(&vs[k], mem(*l))
            }
            _ => vs[k].clone(),
        };
        b.store(&v, &at, l.size() as u64);
    }
}

fn reg_args(vs: &[Val], leaves: &[Leaf]) -> Vec<(Val, &'static str)> {
    vs.iter()
        .zip(leaves)
        .map(|(v, l)| (v.clone(), attr(*l)))
        .collect()
}

/// How a function calls glue: a value in memory, passed by pointer (a clone also writes through a
/// result pointer), or its leaves in registers.
pub enum GlueCall {
    Memory(String),
    Regs(String),
}

/// Declares the drop glue `target` for a value of `ty` and says how to call it.
pub fn drop_callee(
    lay: &Layouts,
    ty: Ty,
    target: &str,
    decls: &mut Vec<(String, String)>,
) -> GlueCall {
    let leaves = lay.leaves(ty);
    match unnative(target) {
        Some(sym) => {
            let n = native(sym);
            decls.push(drop_sig(&leaves).declare(&n));
            if indirect(&leaves) {
                GlueCall::Memory(n)
            } else {
                GlueCall::Regs(n)
            }
        }
        None => {
            decls.push(leaf_sig(Glue::Drop, &leaves).declare(target));
            GlueCall::Regs(target.to_string())
        }
    }
}

/// Declares the clone glue `target` for a value of `ty` and says how to call it.
pub fn clone_callee(
    lay: &Layouts,
    ty: Ty,
    target: &str,
    decls: &mut Vec<(String, String)>,
) -> GlueCall {
    let leaves = lay.leaves(ty);
    match unnative(target) {
        Some(sym) => {
            let n = native(sym);
            decls.push(clone_sig(&leaves).declare(&n));
            if indirect(&leaves) {
                GlueCall::Memory(n)
            } else {
                GlueCall::Regs(n)
            }
        }
        None => {
            decls.push(leaf_sig(Glue::Clone, &leaves).declare(target));
            GlueCall::Regs(target.to_string())
        }
    }
}

/// Calls drop glue `target` (see [`target`]) on the value `vs` of type `ty`.
pub fn call_drop(
    b: &mut FnBuilder,
    decls: &mut Vec<(String, String)>,
    lay: &Layouts,
    target: &str,
    ty: Ty,
    vs: &[Val],
) {
    let leaves = lay.leaves(ty);
    let Some(sym) = unnative(target) else {
        decls.push(leaf_sig(Glue::Drop, &leaves).declare(target));
        b.call(&LTy::Void, "", target, &reg_args(vs, &leaves));
        return;
    };
    let n = native(sym);
    decls.push(drop_sig(&leaves).declare(&n));
    if indirect(&leaves) {
        let slot = b.alloca(&slot_ty(&leaves));
        store_leaves(b, &slot, &leaves, vs);
        b.call(&LTy::Void, "", &n, &[(slot, "")]);
    } else {
        b.call(&LTy::Void, "", &n, &reg_args(vs, &leaves));
    }
}

/// Calls clone glue `target` (see [`target`]) on the value `vs` of type `ty`; the leaves of the
/// copy are named `names` when given.
pub fn call_clone(
    b: &mut FnBuilder,
    decls: &mut Vec<(String, String)>,
    lay: &Layouts,
    target: &str,
    ty: Ty,
    vs: &[Val],
    names: Option<&[Val]>,
) -> Vs {
    let leaves = lay.leaves(ty);
    let (n, native_call) = match unnative(target) {
        Some(sym) => (native(sym), true),
        None => (target.to_string(), false),
    };
    // The leaf symbol of glue that falls back to the translation returns its leaves in registers
    // whatever their size.
    let sig = if native_call {
        clone_sig(&leaves)
    } else {
        leaf_sig(Glue::Clone, &leaves)
    };
    decls.push(sig.declare(&n));
    if native_call && indirect(&leaves) {
        let (src, dst) = (b.alloca(&slot_ty(&leaves)), b.alloca(&slot_ty(&leaves)));
        store_leaves(b, &src, &leaves, vs);
        b.call(&LTy::Void, "", &n, &[(dst.clone(), ""), (src, "")]);
        return load_leaves(b, &dst, &leaves, names);
    }
    // Registers, or the leaf symbol, whose clone signature is the same.
    let args = reg_args(vs, &leaves);
    match leaves.as_slice() {
        [] => {
            b.call(&LTy::Void, "", &n, &args);
            vec![]
        }
        [_] => {
            if let Some(n0) = names {
                b.name_next(&n0[0]);
            }
            vec![b.call(&sig.ret, sig.ret_attr, &n, &args).expect("result")]
        }
        _ => {
            let t = b.call(&sig.ret, "", &n, &args).expect("a tuple");
            (0..leaves.len())
                .map(|k| {
                    if let Some(n0) = names {
                        b.name_next(&n0[k]);
                    }
                    b.extract(&t, k)
                })
                .collect()
        }
    }
}

struct E<'a, 'm, 't> {
    g: &'a mut Gen<'m>,
    b: FnBuilder<'t>,
    cur: String,
    n: u32,
    decls: Vec<(String, String)>,
    /// Symbols of the data objects the glue addresses.
    data: Vec<String>,
}

/// Calls MIR function `f` in the leaf convention with `args` (its parameter leaves), ignoring
/// what it returns.
fn call_func(e: &mut E, f: usize, args: &[Val]) {
    let callee = &e.g.m.funcs[f];
    let (cp, cr) = (e.g.param_leaves(callee), e.g.lay.leaves(callee.ret));
    let sym = e.g.func_symbol(f);
    let (ret, ret_attr) = reg_ret(&cr);
    let sig = Sig {
        params: reg_params(&cp),
        ret,
        ret_attr,
    };
    e.decls.push(sig.declare(&sym));
    let attr = if matches!(cr.as_slice(), [] | [_]) {
        sig.ret_attr
    } else {
        ""
    };
    e.b.call(&sig.ret, attr, &sym, &reg_args(args, &cp));
}

impl E<'_, '_, '_> {
    fn label(&mut self, name: &str) {
        self.b.label(name);
        self.cur = name.to_string();
    }

    fn fresh(&mut self, what: &str) -> String {
        self.n += 1;
        format!("{what}{}", self.n)
    }

    fn br(&mut self, to: &str) {
        self.b.br(to);
    }

    fn test(&mut self, v: &Val) -> Val {
        self.b.icmp("ne", v, &Val::new("0", v.ty.clone()))
    }

    fn if_then(&mut self, cond: &Val, body: impl FnOnce(&mut Self)) {
        let (then, cont) = (self.fresh("t"), self.fresh("c"));
        self.b.cond_br(cond, &then, &cont);
        self.label(&then);
        body(self);
        self.br(&cont);
        self.label(&cont);
    }

    /// Whether the stack pointer is below the running segment's limit (the check a recursive
    /// function starts with, `depth.enter`).
    fn stack_low(&mut self) -> Val {
        self.stack_within(0)
    }

    /// Whether the stack pointer is within `headroom` bytes of the running segment's limit.
    fn stack_within(&mut self, headroom: i64) -> Val {
        let frame = self
            .b
            .call(
                &LTy::Ptr,
                "",
                "llvm.frameaddress.p0",
                &[(Val::new("0", LTy::I32), "")],
            )
            .expect("a pointer");
        let sp = self.b.ptr_to_int(&frame);
        let base = self.b.bin(Bin::And, &sp, &Val::int(!(STACK_REGION - 1)));
        let cell = self
            .b
            .bin(Bin::Add, &base, &Val::int(STACK_REGION - STACK_LIMIT_CELL));
        let cell = self.b.int_to_ptr(&cell);
        let mut limit = self.b.load(&LTy::I64, &cell, 8);
        if headroom != 0 {
            limit = self.b.bin(Bin::Add, &limit, &Val::int(headroom));
        }
        self.b.icmp("ult", &sp, &limit)
    }

    /// Starts a nested drop of recursive data, or parks the value `vs` on the runtime's worklist
    /// and returns when the nesting is at its limit (`msrt_drop_enter`).
    fn park_deep_drop(&mut self, ty: Ty, leaves: &[Leaf], vs: &[Val], deep: &Val) {
        let (enter, body) = (self.fresh("e"), self.fresh("b"));
        self.b.cond_br(deep, &enter, &body);
        self.label(&enter);
        let defer = self.rt("msrt_drop_enter", &[], true).expect("result");
        let defer = self.test(&defer);
        let (park, run) = (self.fresh("p"), self.fresh("r"));
        self.b.cond_br(&defer, &park, &run);
        self.label(&park);
        let blk = self.alloc(&Val::int(mem_layout(leaves).size.max(1) as i64));
        store_leaves(&mut self.b, &blk, leaves, vs);
        let sym = self.g.glue_symbol(Glue::SlotDrop, ty);
        self.decls
            .push(leaf_sig(Glue::SlotDrop, leaves).declare(&sym));
        let (f, p) = (
            self.b.ptrtoint(&Val::new(format!("@\"{sym}\""), LTy::Ptr)),
            self.b.ptrtoint(&blk),
        );
        self.rt("msrt_drop_defer", &[&f, &p], false);
        self.b.ret(None);
        self.label(&run);
        self.br(&body);
        self.label(&body);
    }

    fn declare(&mut self, name: &str, ret: &str, params: &str) {
        self.decls.push((
            name.to_string(),
            format!("declare {ret} @\"{name}\"({params}) nounwind"),
        ));
    }

    /// Calls the runtime function `name` (all arguments `i64`); the result is an `i64`.
    fn rt(&mut self, name: &str, args: &[&Val], ret: bool) -> Option<Val> {
        let params = vec!["i64"; args.len()].join(", ");
        self.declare(name, if ret { "i64" } else { "void" }, &params);
        let a: Vec<(Val, &str)> = args.iter().map(|v| ((*v).clone(), "")).collect();
        self.b
            .call(if ret { &LTy::I64 } else { &LTy::Void }, "", name, &a)
    }

    /// Frees the block at `p` (a pointer or its `i64` address); the runtime's `free` takes a pointer so LLVM
    /// pairs it with the allocation.
    fn free(&mut self, p: &Val) {
        self.declare_heap("msrt_free");
        let ptr = if p.ty == LTy::Ptr {
            p.clone()
        } else {
            self.b.inttoptr(p)
        };
        self.b.call(&LTy::Void, "", "msrt_free", &[(ptr, "")]);
    }

    fn declare_heap(&mut self, name: &str) {
        let decl = crate::mir_llvm::rt::heap_decl(name).expect("a heap function");
        self.decls.push((name.to_string(), decl.to_string()));
    }

    /// A fresh block of `size` bytes.
    fn alloc(&mut self, size: &Val) -> Val {
        self.declare_heap("msrt_alloc");
        self.b
            .call(
                &LTy::Ptr,
                "noalias align 16 ",
                "msrt_alloc",
                &[(size.clone(), "")],
            )
            .expect("result")
    }

    fn ptr_of(&mut self, addr: &Val) -> Val {
        self.b.inttoptr(addr)
    }

    /// The symbol to call for glue `kind` of `ty`.
    fn glue_sym(&mut self, kind: Glue, ty: Ty) -> String {
        let sym = self.g.glue_symbol(kind, ty);
        target(self.g, kind, ty, sym)
    }

    fn drop_value(&mut self, ty: Ty, vs: &[Val]) {
        match own_kind(&self.g.lay, ty) {
            OwnKind::Identity => {}
            OwnKind::Str => {
                // Only an owned string (tag `00`) frees anything.
                let owned = self.b.icmp("ult", &vs[1], &Val::int(STR_INLINE as i64));
                self.if_then(&owned, |s| {
                    s.rt("msrt_str_free", &[&vs[0]], false);
                });
            }
            OwnKind::Obj => {
                self.rt("msrt_obj_drop", &[&vs[0]], false);
            }
            OwnKind::Glue => {
                let sym = self.glue_sym(Glue::Drop, ty);
                call_drop(&mut self.b, &mut self.decls, &self.g.lay, &sym, ty, vs);
            }
        }
    }

    /// Drops the value of type `ty` stored at `p`, in place when it travels by pointer.
    fn drop_at(&mut self, ty: Ty, p: &Val) {
        let leaves = self.g.lay.leaves(ty);
        let sym = (own_kind(&self.g.lay, ty) == OwnKind::Glue && indirect(&leaves))
            .then(|| self.glue_sym(Glue::Drop, ty))
            .filter(|s| unnative(s).is_some());
        if let Some(sym) = sym {
            self.decls.push(drop_sig(&leaves).declare(&sym));
            self.b.call(&LTy::Void, "", &sym, &[(p.clone(), "")]);
        } else if own_kind(&self.g.lay, ty) != OwnKind::Identity {
            let vs = load_leaves(&mut self.b, p, &leaves, None);
            self.drop_value(ty, &vs);
        }
    }

    fn clone_value(&mut self, ty: Ty, vs: &[Val]) -> Vs {
        match own_kind(&self.g.lay, ty) {
            OwnKind::Identity => vs.to_vec(),
            OwnKind::Str => {
                let (pre, dup, join) = (self.cur.clone(), self.fresh("d"), self.fresh("j"));
                let out = clone_str(&mut self.b, &mut self.decls, (&pre, &dup, &join), vs, None);
                self.cur = join;
                out
            }
            OwnKind::Obj => vec![self.rt("msrt_obj_clone", &[&vs[0]], true).expect("result")],
            OwnKind::Glue => {
                let sym = self.glue_sym(Glue::Clone, ty);
                call_clone(
                    &mut self.b,
                    &mut self.decls,
                    &self.g.lay,
                    &sym,
                    ty,
                    vs,
                    None,
                )
            }
        }
    }

    /// Stores a clone of the value of type `ty` at `src` into `dst`, building it in place when
    /// it travels by pointer.
    fn clone_at(&mut self, ty: Ty, src: &Val, dst: &Val) {
        let leaves = self.g.lay.leaves(ty);
        let sym = (own_kind(&self.g.lay, ty) == OwnKind::Glue && indirect(&leaves))
            .then(|| self.glue_sym(Glue::Clone, ty))
            .filter(|s| unnative(s).is_some());
        if let Some(sym) = sym {
            self.decls.push(clone_sig(&leaves).declare(&sym));
            self.b.call(
                &LTy::Void,
                "",
                &sym,
                &[(dst.clone(), ""), (src.clone(), "")],
            );
        } else {
            let vs = load_leaves(&mut self.b, src, &leaves, None);
            let out = self.clone_value(ty, &vs);
            store_leaves(&mut self.b, dst, &leaves, &out);
        }
    }

    /// The fields of a plain type: `(type, first leaf, width)`.
    fn fields_of(&self, ty: Ty) -> Vec<(Ty, usize, usize)> {
        let TyKind::Type(r) = self.g.m.types.kind(ty) else {
            return Vec::new();
        };
        let mut at = 0;
        self.g.m.type_defs[r.index()]
            .fields
            .iter()
            .map(|f| {
                let w = self.g.lay.width(f.1);
                at += w;
                (f.1, at - w, w)
            })
            .collect()
    }

    /// Runs `body(i)` for `i` in `0..len`.
    fn count(&mut self, len: &Val, body: impl FnOnce(&mut Self, &Val)) {
        let (head, bod, latch, done) = (
            self.fresh("h"),
            self.fresh("b"),
            self.fresh("l"),
            self.fresh("e"),
        );
        let pre = self.cur.clone();
        self.br(&head);
        self.label(&head);
        let i = self.b.reserve(LTy::I64);
        let next = self.b.reserve(LTy::I64);
        self.b
            .phi(&i, &[(Val::int(0), pre), (next.clone(), latch.clone())]);
        let more = self.b.icmp("slt", &i, len);
        self.b.cond_br(&more, &bod, &done);
        self.label(&bod);
        body(self, &i);
        // The back edge leaves from a block of its own, whatever blocks `body` made.
        self.br(&latch);
        self.label(&latch);
        self.b.name_next(&next);
        self.b.bin(Bin::Add, &i, &Val::int(1));
        self.br(&head);
        self.label(&done);
    }

    fn drop_list(&mut self, ty: Ty, ptr: &Val, len: &Val) {
        let m = self.g.m;
        if let Some(e) = m.list_elem(ty).filter(|e| m.needs_drop(*e)) {
            let et = slot_ty(&self.g.lay.leaves(e));
            let base = self.ptr_of(ptr);
            self.count(len, |s, i| {
                let at = s.b.elem_ptr(&et, &base, i);
                s.drop_at(e, &at);
            });
        }
        let nn = self.test(ptr);
        self.if_then(&nn, |s| s.free(ptr));
    }

    fn glue_drop(&mut self, ty: Ty, vs: &[Val]) {
        let m = self.g.m;
        match m.types.kind(ty).clone() {
            TyKind::Bytes | TyKind::List(_) => {
                let owned = self.test(&vs[2]);
                self.if_then(&owned, |s| s.drop_list(ty, &vs[0], &vs[1]));
            }
            TyKind::Type(r) if m.type_defs[r.index()].indirect => self.drop_indirect(r, &vs[0]),
            TyKind::Type(_) => {
                for (fty, at, w) in self.fields_of(ty) {
                    if m.needs_drop(fty) {
                        self.drop_value(fty, &vs[at..at + w]);
                    }
                }
            }
            TyKind::Opt(inner) if self.g.lay.opt_is_boxed(inner) => {
                let nn = self.test(&vs[0]);
                self.if_then(&nn, |s| {
                    let p = s.ptr_of(&vs[0]);
                    if m.needs_drop(inner) {
                        s.drop_at(inner, &p);
                    }
                    s.free(&vs[0]);
                });
            }
            TyKind::Opt(_) if self.g.lay.is_str_like(ty) => self.drop_value(ty, vs),
            TyKind::Opt(inner) => {
                let present = self.test(&vs[0]);
                self.if_then(&present, |s| s.drop_value(inner, &vs[1..]));
            }
            TyKind::Obj(..) => self.drop_obj(ty, vs),
            TyKind::Iface(_) => self.drop_iface(vs),
            TyKind::Alt(a) => self.drop_alt(ty, a, vs),
            _ => {}
        }
    }

    /// Drops the fields of the indirect type whose block is `p`, then frees the block and the
    /// header blocks of its collections (a collection that was never filled has none).
    fn drop_indirect(&mut self, r: ms_mir::types::TypeId, p: &Val) {
        let m = self.g.m;
        let block = self.g.lay.type_block(r);
        let offsets = mem_layout(&block).offsets;
        let base = self.ptr_of(p);
        let mut at = 0;
        for f in &m.type_defs[r.index()].fields {
            let boxed = self.g.lay.type_field_boxed(f.1);
            let n = if boxed { 1 } else { self.g.lay.width(f.1) };
            let (bk, fty) = (at, f.1);
            at += n;
            if boxed {
                let bp = self.load_block_leaf(&base, offsets[bk], block[bk]);
                let nn = self.test(&bp);
                self.if_then(&nn, |s| {
                    if m.needs_drop(fty) {
                        let hp = s.ptr_of(&bp);
                        let words: Vec<Val> = (0..ms_rt_abi::MAP_SIZE / 8)
                            .map(|k| s.load_block_leaf(&hp, (k * 8) as u32, Leaf::I64))
                            .collect();
                        s.drop_value(fty, &words);
                    }
                    s.free(&bp);
                });
            } else if m.needs_drop(fty) {
                let fv: Vec<Val> = (bk..bk + n)
                    .map(|k| self.load_block_leaf(&base, offsets[k], block[k]))
                    .collect();
                self.drop_value(fty, &fv);
            }
        }
        self.free(p);
    }

    /// The symbol of a data object the glue addresses, as a pointer.
    fn data_addr(&mut self, sym: String) -> Val {
        self.data.push(sym.clone());
        Val::new(format!("@\"{sym}\""), LTy::Ptr)
    }

    /// A map or set is an owned value the runtime drops through its descriptor.
    fn drop_obj(&mut self, ty: Ty, vs: &[Val]) {
        let leaves = self.g.lay.leaves(ty);
        let slot = self.b.alloca(&slot_ty(&leaves));
        store_leaves(&mut self.b, &slot, &leaves, vs);
        let slot = self.b.ptrtoint(&slot);
        let sym = self.g.typedesc_symbol(ty);
        let desc = self.data_addr(sym);
        let desc = self.b.ptrtoint(&desc);
        self.rt("msrt_slot_drop", &[&desc, &slot], false);
    }

    /// The vtable word's low bits say what the value owns: 0 the box and its payload (`vtable[0]`
    /// is the payload destructor), 1 only the box (`iface.borrow`), 2 nothing (`iface.view`).
    fn drop_iface(&mut self, vs: &[Val]) {
        let (data, vt) = (&vs[0], &vs[1]);
        let tag = self.b.bin(Bin::And, vt, &Val::int(3));
        let owned = self.b.icmp("eq", &tag, &Val::int(0));
        self.if_then(&owned, |s| {
            let at = s.ptr_of(vt);
            let f = s.b.load(&LTy::I64, &at, 8);
            let f = s.b.inttoptr(&f);
            s.b.call_ptr(&LTy::Void, "", &f, &[(data.clone(), "")]);
        });
        let borrowed = self.b.icmp("eq", &tag, &Val::int(1));
        self.if_then(&borrowed, |s| s.free(data));
    }

    /// Loads the block leaf `l` at byte `off` of `p`, widened to the register it travels in.
    fn load_block_leaf(&mut self, p: &Val, off: u32, l: Leaf) -> Val {
        let at = self.b.gep_bytes(p, u64::from(off));
        let v = self.b.load(&mem(l), &at, l.size() as u64);
        match l {
            Leaf::N8 | Leaf::N16 | Leaf::N32 => self.b.sext(&v, LTy::I64),
            Leaf::U8 | Leaf::U16 | Leaf::U32 => self.b.zext(&v, LTy::I64),
            _ => v,
        }
    }

    /// Frees the block `p` of a boxed enum whose case index is `tag`, unless the case has no
    /// payload: such values are one shared static block.
    fn free_boxed(&mut self, a: ms_mir::types::AltId, tag: &Val, p: &Val) {
        let units: Vec<usize> = self.g.m.alts[a.index()]
            .cases
            .iter()
            .enumerate()
            .filter(|(_, c)| c.fields.is_empty())
            .map(|(i, _)| i)
            .collect();
        let (free, cont) = (self.fresh("f"), self.fresh("c"));
        if units.is_empty() {
            self.free(p);
            return;
        }
        let mut unit: Option<Val> = None;
        for c in units {
            let is = self.b.icmp("eq", tag, &Val::int(c as i64));
            unit = Some(match unit {
                None => is,
                Some(u) => self.b.bin(Bin::Or, &u, &is),
            });
        }
        self.b.cond_br(&unit.expect("a unit case"), &cont, &free);
        self.label(&free);
        self.free(p);
        self.br(&cont);
        self.label(&cont);
    }

    /// The field of `case` that holds the same boxed enum again (the tail of a chain such as
    /// `Cons(head, tail)`): `(field, leaves, optional)`. Dropping loops over it, so a long chain
    /// does not overflow the stack.
    fn tail_field(&self, ty: Ty, case: &[(Ty, Vec<usize>)]) -> Option<(usize, Vec<usize>, bool)> {
        case.iter().enumerate().rev().find_map(|(i, (fty, idx))| {
            if *fty == ty && idx.len() == 1 {
                return Some((i, idx.clone(), false));
            }
            match self.g.m.types.kind(*fty) {
                TyKind::Opt(inner) if *inner == ty && idx.len() == 2 => {
                    Some((i, idx.clone(), true))
                }
                _ => None,
            }
        })
    }

    /// Drops what an enum owns: the payload fields of its case, then (boxed) the block.
    fn drop_alt(&mut self, ty: Ty, a: ms_mir::types::AltId, vs: &[Val]) {
        let m = self.g.m;
        let fields = self.g.lay.alt_fields(a);
        let boxed = match &self.g.lay.shape(ty).alt {
            Some(AltRepr::Boxed { block, .. }) => Some(block.clone()),
            _ => None,
        };
        let droppable = |c: usize, case: &Vec<(Ty, Vec<usize>)>| {
            !m.alts[a.index()].borrows(c) && case.iter().any(|(t, _)| m.needs_drop(*t))
        };
        let Some(block) = boxed else {
            for (c, case) in fields.iter().enumerate().filter(|(c, k)| droppable(*c, k)) {
                let is = self.b.icmp("eq", &vs[0], &Val::int(c as i64));
                self.if_then(&is, |s| {
                    for (fty, idx) in case.iter().filter(|(t, _)| m.needs_drop(*t)) {
                        let fv: Vec<Val> = idx.iter().map(|i| vs[*i].clone()).collect();
                        s.drop_value(*fty, &fv);
                    }
                });
            }
            return;
        };
        let offsets = mem_layout(&block).offsets;
        let chain = fields.iter().any(|c| self.tail_field(ty, c).is_some());
        // The head of the loop: the block being dropped.
        let (head, latch, exit) = (self.fresh("h"), self.fresh("l"), self.fresh("e"));
        let pre = self.cur.clone();
        let (cur, next) = (self.b.reserve(LTy::I64), self.b.reserve(LTy::I64));
        if chain {
            self.br(&head);
            self.label(&head);
            self.b
                .phi(&cur, &[(vs[0].clone(), pre), (next.clone(), latch.clone())]);
        }
        let first = if chain { cur.clone() } else { vs[0].clone() };
        let base = self.ptr_of(&first);
        let tag = self.load_block_leaf(&base, 0, Leaf::I64);
        let mut back: Vec<(Val, String)> = Vec::new();
        for (c, case) in fields.iter().enumerate().filter(|(c, k)| droppable(*c, k)) {
            let tail = self.tail_field(ty, case);
            let (this, other) = (self.fresh("t"), self.fresh("o"));
            let is = self.b.icmp("eq", &tag, &Val::int(c as i64));
            self.b.cond_br(&is, &this, &other);
            self.label(&this);
            for (i, (fty, idx)) in case.iter().enumerate() {
                if !m.needs_drop(*fty) || tail.as_ref().is_some_and(|t| t.0 == i) {
                    continue;
                }
                let fv: Vec<Val> = idx
                    .iter()
                    .map(|k| self.load_block_leaf(&base, offsets[*k], block[*k]))
                    .collect();
                self.drop_value(*fty, &fv);
            }
            match tail {
                Some((_, idx, optional)) => {
                    let k = *idx.last().expect("tail leaf");
                    let child = self.load_block_leaf(&base, offsets[k], block[k]);
                    let present = optional.then(|| {
                        let p = self.load_block_leaf(&base, offsets[idx[0]], block[idx[0]]);
                        self.test(&p)
                    });
                    self.free(&first);
                    back.push((child, self.cur.clone()));
                    match present {
                        Some(p) => self.b.cond_br(&p, &latch, &exit),
                        None => self.br(&latch),
                    }
                }
                None => {
                    self.free(&first);
                    self.br(&exit);
                }
            }
            self.label(&other);
        }
        // A case with nothing to drop: only the block is freed.
        self.free_boxed(a, &tag, &first);
        self.br(&exit);
        if chain {
            self.label(&latch);
            self.b.phi(&next, &back);
            self.br(&head);
        }
        self.label(&exit);
    }

    /// Clones the indirect type whose block is `p`: a new block over clones of the fields. A
    /// collection field lives behind a header block of its own, which the copy gets too (none
    /// when the original has none).
    fn clone_indirect(&mut self, r: ms_mir::types::TypeId, p: &Val) -> Vs {
        let m = self.g.m;
        let block = self.g.lay.type_block(r);
        let base = self.ptr_of(p);
        let loaded = load_leaves(&mut self.b, &base, &block, None);
        let mut out = loaded.clone();
        let mut at = 0;
        for f in &m.type_defs[r.index()].fields {
            let boxed = self.g.lay.type_field_boxed(f.1);
            let n = if boxed { 1 } else { self.g.lay.width(f.1) };
            let (bk, fty) = (at, f.1);
            at += n;
            if boxed {
                let (yes, join) = (self.fresh("y"), self.fresh("j"));
                let pre = self.cur.clone();
                let nn = self.test(&loaded[bk]);
                self.b.cond_br(&nn, &yes, &join);
                self.label(&yes);
                let hp = self.ptr_of(&loaded[bk]);
                let words = load_leaves(
                    &mut self.b,
                    &hp,
                    &[Leaf::I64; ms_rt_abi::MAP_SIZE / 8],
                    None,
                );
                let words = if m.needs_drop(fty) {
                    self.clone_value(fty, &words)
                } else {
                    words
                };
                let header = self.alloc(&Val::int(ms_rt_abi::MAP_SIZE as i64));
                store_leaves(&mut self.b, &header, &vec![Leaf::I64; words.len()], &words);
                let header = self.b.ptrtoint(&header);
                self.br(&join);
                let end = self.cur.clone();
                self.label(&join);
                let h = self.b.reserve(LTy::I64);
                self.b.phi(&h, &[(Val::int(0), pre), (header, end)]);
                out[bk] = h;
            } else if m.needs_drop(fty) {
                let cv = self.clone_value(fty, &loaded[bk..bk + n]);
                out[bk..bk + n].clone_from_slice(&cv);
            }
        }
        let blk = self.alloc(&Val::int(mem_layout(&block).size as i64));
        store_leaves(&mut self.b, &blk, &block, &out);
        vec![self.b.ptrtoint(&blk)]
    }

    /// For a boxed enum with payloadless cases: whether `tag` names one (such values are one
    /// shared static block) and that block's address as a word.
    fn unit_case(&mut self, a: ms_mir::types::AltId, tag: &Val, size: u32) -> Option<(Val, Val)> {
        let units: Vec<usize> = self.g.m.alts[a.index()]
            .cases
            .iter()
            .enumerate()
            .filter(|(_, c)| c.fields.is_empty())
            .map(|(i, _)| i)
            .collect();
        let mut acc: Option<(Val, Val)> = None;
        for c in units {
            let sym = self.g.unit_block_symbol(a, c, size as usize);
            let addr = self.data_addr(sym);
            let addr = self.b.ptrtoint(&addr);
            let is = self.b.icmp("eq", tag, &Val::int(c as i64));
            acc = Some(match acc {
                None => (is, addr),
                Some((u, prev)) => (
                    self.b.bin(Bin::Or, &u, &is),
                    self.b.select(&is, &addr, &prev),
                ),
            });
        }
        acc
    }

    /// Clones an enum: the fields of its case, then (boxed) a new block unless the case has no
    /// payload. A boxed enum whose case holds the enum again is copied front to back in a loop,
    /// so a long chain does not overflow the stack.
    fn clone_alt(&mut self, ty: Ty, a: ms_mir::types::AltId, vs: &[Val]) -> Vs {
        let m = self.g.m;
        let fields = self.g.lay.alt_fields(a);
        let shape = self.g.lay.shape(ty);
        let (leaves, boxed) = match &shape.alt {
            Some(AltRepr::Boxed { block, .. }) => (block.clone(), true),
            _ => (shape.leaves.clone(), false),
        };
        if boxed && fields.iter().any(|c| self.tail_field(ty, c).is_some()) {
            return vec![self.clone_chain(ty, a, &fields, &leaves, &vs[0])];
        }
        let src = if boxed {
            let p = self.ptr_of(&vs[0]);
            load_leaves(&mut self.b, &p, &leaves, None)
        } else {
            vs.to_vec()
        };
        let tag = src[0].clone();
        let join = self.fresh("j");
        let mut incoming: Vec<Vec<(Val, String)>> = vec![Vec::new(); leaves.len()];
        for (c, case) in fields.iter().enumerate() {
            if !case.iter().any(|(t, _)| m.needs_drop(*t)) {
                continue;
            }
            let (this, other) = (self.fresh("t"), self.fresh("o"));
            let is = self.b.icmp("eq", &tag, &Val::int(c as i64));
            self.b.cond_br(&is, &this, &other);
            self.label(&this);
            let mut out = src.clone();
            for (fty, idx) in case.iter().filter(|(t, _)| m.needs_drop(*t)) {
                let fv: Vs = idx.iter().map(|i| src[*i].clone()).collect();
                let cv = self.clone_value(*fty, &fv);
                for (i, v) in idx.iter().zip(cv) {
                    out[*i] = v;
                }
            }
            for (k, v) in out.into_iter().enumerate() {
                incoming[k].push((v, self.cur.clone()));
            }
            self.br(&join);
            self.label(&other);
        }
        for (k, v) in src.iter().enumerate() {
            incoming[k].push((v.clone(), self.cur.clone()));
        }
        self.br(&join);
        self.label(&join);
        let out: Vs = src
            .iter()
            .zip(&incoming)
            .map(|(s, inc)| {
                let r = self.b.reserve(s.ty.clone());
                self.b.phi(&r, inc);
                r
            })
            .collect();
        if !boxed {
            return out;
        }
        let size = mem_layout(&leaves).size;
        let fresh = |s: &mut Self, out: &Vs| {
            let blk = s.alloc(&Val::int(i64::from(size.max(1))));
            store_leaves(&mut s.b, &blk, &leaves, out);
            s.b.ptrtoint(&blk)
        };
        let Some((unit, addr)) = self.unit_case(a, &out[0], size) else {
            return vec![fresh(self, &out)];
        };
        let (new, fin) = (self.fresh("n"), self.fresh("f"));
        let pre = self.cur.clone();
        self.b.cond_br(&unit, &fin, &new);
        self.label(&new);
        let blk = fresh(self, &out);
        self.br(&fin);
        let end = self.cur.clone();
        self.label(&fin);
        let r = self.b.reserve(LTy::I64);
        self.b.phi(&r, &[(addr, pre), (blk, end)]);
        vec![r]
    }

    /// Copies a chain of boxed blocks front to back: each iteration allocates the new block,
    /// stores its address where the previous block's tail pointer lives, clones the non-tail
    /// fields, and continues with the source's tail. Returns the first new block.
    fn clone_chain(
        &mut self,
        ty: Ty,
        a: ms_mir::types::AltId,
        fields: &[Vec<(Ty, Vec<usize>)>],
        block: &[Leaf],
        first: &Val,
    ) -> Val {
        let m = self.g.m;
        let offsets = mem_layout(block).offsets;
        let size = mem_layout(block).size;
        let result = self.b.alloca(&LTy::I64);
        let res_addr = self.b.ptrtoint(&result);
        let (head, latch, exit) = (self.fresh("h"), self.fresh("l"), self.fresh("e"));
        let pre = self.cur.clone();
        let (src, dst) = (self.b.reserve(LTy::I64), self.b.reserve(LTy::I64));
        let (next_src, next_dst) = (self.b.reserve(LTy::I64), self.b.reserve(LTy::I64));
        self.br(&head);
        self.label(&head);
        self.b.phi(
            &src,
            &[
                (first.clone(), pre.clone()),
                (next_src.clone(), latch.clone()),
            ],
        );
        self.b
            .phi(&dst, &[(res_addr, pre), (next_dst.clone(), latch.clone())]);
        let sp = self.ptr_of(&src);
        let sv = load_leaves(&mut self.b, &sp, block, None);
        let tag = sv[0].clone();
        let dp = self.ptr_of(&dst);
        if let Some((unit, addr)) = self.unit_case(a, &tag, size) {
            // A payloadless case is the shared block: link it and stop.
            let (shared, fresh) = (self.fresh("s"), self.fresh("n"));
            self.b.cond_br(&unit, &shared, &fresh);
            self.label(&shared);
            self.b.store(&addr, &dp, 8);
            self.br(&exit);
            self.label(&fresh);
        }
        let blk = self.alloc(&Val::int(i64::from(size.max(1))));
        let blk_word = self.b.ptrtoint(&blk);
        self.b.store(&blk_word, &dp, 8);
        let mut back: Vec<(Val, Val, String)> = Vec::new();
        for (c, case) in fields.iter().enumerate() {
            if !case.iter().any(|(t, _)| m.needs_drop(*t)) {
                continue;
            }
            let tail = self.tail_field(ty, case);
            let (this, other) = (self.fresh("t"), self.fresh("o"));
            let is = self.b.icmp("eq", &tag, &Val::int(c as i64));
            self.b.cond_br(&is, &this, &other);
            self.label(&this);
            let mut out = sv.clone();
            for (i, (fty, idx)) in case.iter().enumerate() {
                if !m.needs_drop(*fty) || tail.as_ref().is_some_and(|t| t.0 == i) {
                    continue;
                }
                let fv: Vs = idx.iter().map(|k| sv[*k].clone()).collect();
                let cv = self.clone_value(*fty, &fv);
                for (k, v) in idx.iter().zip(cv) {
                    out[*k] = v;
                }
            }
            store_leaves(&mut self.b, &blk, block, &out);
            match tail {
                Some((_, idx, optional)) => {
                    let k = *idx.last().expect("tail leaf");
                    let at = self.b.gep_bytes(&blk, u64::from(offsets[k]));
                    let at = self.b.ptrtoint(&at);
                    back.push((sv[k].clone(), at, self.cur.clone()));
                    if optional {
                        let present = self.test(&sv[idx[0]]);
                        self.b.cond_br(&present, &latch, &exit);
                    } else {
                        self.br(&latch);
                    }
                }
                None => self.br(&exit),
            }
            self.label(&other);
        }
        store_leaves(&mut self.b, &blk, block, &sv);
        self.br(&exit);
        self.label(&latch);
        let srcs: Vec<(Val, String)> = back
            .iter()
            .map(|(s, _, l)| (s.clone(), l.clone()))
            .collect();
        let dsts: Vec<(Val, String)> = back
            .iter()
            .map(|(_, d, l)| (d.clone(), l.clone()))
            .collect();
        self.b.phi(&next_src, &srcs);
        self.b.phi(&next_dst, &dsts);
        self.br(&head);
        self.label(&exit);
        self.b.load(&LTy::I64, &result, 8)
    }

    fn list_copy(&mut self, ty: Ty, vs: &[Val]) -> Vs {
        let m = self.g.m;
        let elem = m.list_elem(ty);
        let (ptr, len) = (&vs[0], &vs[1]);
        let leaves = elem.map(|e| self.g.lay.leaves(e));
        let (size, align) = leaves.as_ref().map_or((1, 1), |l| {
            let lay = mem_layout(l);
            (lay.size.max(1) as i64, lay.align as u64)
        });
        let (some, join) = (self.fresh("s"), self.fresh("j"));
        let pre = self.cur.clone();
        let nonempty = self.test(len);
        self.b.cond_br(&nonempty, &some, &join);
        self.label(&some);
        let bytes = self.b.bin(Bin::Mul, len, &Val::int(size));
        let np = self.alloc(&bytes);
        let src = self.ptr_of(ptr);
        match elem.filter(|e| m.needs_drop(*e)) {
            None => self.b.memcpy((&np, align), (&src, align), &bytes),
            Some(e) => {
                let et = slot_ty(&leaves.expect("element"));
                self.count(len, |s, i| {
                    let from = s.b.elem_ptr(&et, &src, i);
                    let to = s.b.elem_ptr(&et, &np, i);
                    s.clone_at(e, &from, &to);
                });
            }
        }
        let np = self.b.ptrtoint(&np);
        self.br(&join);
        let end = self.cur.clone();
        self.label(&join);
        let p = self.b.reserve(LTy::I64);
        self.b.phi(&p, &[(Val::int(0), pre), (np, end)]);
        vec![p, len.clone(), len.clone()]
    }

    fn glue_copy(&mut self, ty: Ty, vs: &[Val]) -> Vs {
        let m = self.g.m;
        match m.types.kind(ty).clone() {
            TyKind::Bytes | TyKind::List(_) => self.list_copy(ty, vs),
            TyKind::Type(r) if m.type_defs[r.index()].indirect => self.clone_indirect(r, &vs[0]),
            TyKind::Alt(a) => self.clone_alt(ty, a, vs),
            TyKind::Type(_) => {
                let mut out = Vec::new();
                for (fty, at, w) in self.fields_of(ty) {
                    out.extend(self.clone_value(fty, &vs[at..at + w]));
                }
                out
            }
            TyKind::Opt(inner) if self.g.lay.opt_is_boxed(inner) => {
                let leaves = self.g.lay.leaves(inner);
                let size = mem_layout(&leaves).size as i64;
                let (yes, join) = (self.fresh("y"), self.fresh("j"));
                let pre = self.cur.clone();
                let nn = self.test(&vs[0]);
                self.b.cond_br(&nn, &yes, &join);
                self.label(&yes);
                let src = self.ptr_of(&vs[0]);
                let q = self.alloc(&Val::int(size.max(1)));
                self.clone_at(inner, &src, &q);
                let q = self.b.ptrtoint(&q);
                self.br(&join);
                let end = self.cur.clone();
                self.label(&join);
                let p = self.b.reserve(LTy::I64);
                self.b.phi(&p, &[(vs[0].clone(), pre), (q, end)]);
                vec![p]
            }
            TyKind::Opt(_) if self.g.lay.is_str_like(ty) => self.clone_value(ty, vs),
            TyKind::Opt(inner) if self.g.lay.opt_is_nullable(inner) => {
                vec![self.rt("msrt_obj_clone", &[&vs[0]], true).expect("result")]
            }
            TyKind::Opt(inner) => {
                let payload = vs[1..].to_vec();
                let (yes, join) = (self.fresh("y"), self.fresh("j"));
                let pre = self.cur.clone();
                let present = self.test(&vs[0]);
                self.b.cond_br(&present, &yes, &join);
                self.label(&yes);
                let c = self.clone_value(inner, &payload);
                self.br(&join);
                let end = self.cur.clone();
                self.label(&join);
                let mut out = vec![vs[0].clone()];
                for (k, p) in payload.iter().enumerate() {
                    let r = self.b.reserve(p.ty.clone());
                    self.b
                        .phi(&r, &[(p.clone(), pre.clone()), (c[k].clone(), end.clone())]);
                    out.push(r);
                }
                out
            }
            TyKind::Obj(..) => {
                // Map and Set are owned values the runtime copies through their descriptor.
                let leaves = self.g.lay.leaves(ty);
                let (src, dst) = (
                    self.b.alloca(&slot_ty(&leaves)),
                    self.b.alloca(&slot_ty(&leaves)),
                );
                store_leaves(&mut self.b, &src, &leaves, vs);
                let desc = {
                    let sym = self.g.typedesc_symbol(ty);
                    let addr = self.data_addr(sym);
                    self.b.ptrtoint(&addr)
                };
                let (from, to) = (self.b.ptrtoint(&src), self.b.ptrtoint(&dst));
                self.rt("msrt_slot_copy", &[&desc, &from, &to], false);
                load_leaves(&mut self.b, &dst, &leaves, None)
            }
            TyKind::Iface(i) => {
                // The payload copier sits after the methods in the vtable. The copy owns its
                // payload whatever the source owned, so the tag bits come off.
                let vt = self.b.bin(Bin::And, &vs[1], &Val::int(!3));
                let slot = 8 * (1 + m.ifaces[i.index()].methods.len()) as i64;
                let at = self.b.bin(Bin::Add, &vt, &Val::int(slot));
                let at = self.ptr_of(&at);
                let copier = self.b.load(&LTy::Ptr, &at, 8);
                let data = self
                    .b
                    .call_ptr(&LTy::I64, "", &copier, &[(vs[0].clone(), "")])
                    .expect("result");
                vec![data, vt]
            }
            _ => vs.to_vec(),
        }
    }
}

/// Emits the glue `kind` for `ty`, which `supports` accepted, with its leaf thunk. `loc` is the
/// `DILocation` node of each function.
pub fn emit(g: &mut Gen, kind: Glue, ty: Ty, types: &Types, loc: usize) -> Emitted {
    let leaves = g.lay.leaves(ty);
    let sig = native_sig(kind, &leaves);
    let mut e = E {
        g,
        b: FnBuilder::new(types, Some(loc)),
        cur: String::new(),
        n: 0,
        decls: Vec::new(),
        data: Vec::new(),
    };
    e.label("entry");
    let a = |i: usize, t: LTy| Val::new(format!("%a{i}"), t);
    // The value parameter as leaves: registers as they come, a pointer loaded.
    let value = |e: &mut E, at: usize| -> Vs {
        if indirect(&leaves) {
            load_leaves(&mut e.b, &a(at, LTy::Ptr), &leaves, None)
        } else {
            leaves
                .iter()
                .enumerate()
                .map(|(k, l)| a(at + k, reg(*l)))
                .collect()
        }
    };
    match kind {
        Glue::Drop => {
            let vs = value(&mut e, 0);
            // Data that can contain itself bounds its nesting (`ms_rt::dropq`): past the limit
            // the value is parked on the runtime's worklist and dropped later.
            let bounded = e.g.m.drop_recurses(ty);
            let deep = bounded.then(|| e.stack_within(DEEP_DROP_HEADROOM));
            if let Some(deep) = &deep {
                e.park_deep_drop(ty, &leaves, &vs, deep);
            }
            e.glue_drop(ty, &vs);
            if let Some(deep) = &deep {
                e.if_then(deep, |e| {
                    e.rt("msrt_drop_leave", &[], false);
                });
            }
            e.b.ret(None);
        }
        Glue::Clone => {
            let sret = indirect(&leaves);
            let vs = value(&mut e, usize::from(sret));
            let ret = |e: &mut E, out: &[Val]| {
                if sret {
                    store_leaves(&mut e.b, &a(0, LTy::Ptr), &leaves, out);
                    e.b.ret(None);
                } else {
                    match out {
                        [] => e.b.ret(None),
                        [one] => e.b.ret(Some(one)),
                        many => e.b.ret_multi(many),
                    }
                }
            };
            // Recursive data copies on a new stack segment when this one is nearly used up.
            if e.g.m.drop_recurses(ty) {
                let low = e.stack_low();
                let (grow, cont) = (e.fresh("g"), e.fresh("c"));
                e.b.cond_br(&low, &grow, &cont);
                e.label(&grow);
                let (src, dst) = (e.b.alloca(&slot_ty(&leaves)), e.b.alloca(&slot_ty(&leaves)));
                store_leaves(&mut e.b, &src, &leaves, &vs);
                let sym = e.g.glue_symbol(Glue::SlotCopy, ty);
                e.decls
                    .push(leaf_sig(Glue::SlotCopy, &leaves).declare(&sym));
                let f = e.b.ptrtoint(&Val::new(format!("@\"{sym}\""), LTy::Ptr));
                let (s, d) = (e.b.ptrtoint(&src), e.b.ptrtoint(&dst));
                e.rt("msrt_slot_copy_grown", &[&f, &s, &d], false);
                let out = load_leaves(&mut e.b, &dst, &leaves, None);
                ret(&mut e, &out);
                e.label(&cont);
            }
            let out = e.glue_copy(ty, &vs);
            ret(&mut e, &out);
        }
        Glue::BlockDrop => {
            let p = a(0, LTy::Ptr);
            e.drop_at(ty, &p);
            e.free(&p);
            e.b.ret(None);
        }
        Glue::BlockClone => {
            let src = a(0, LTy::Ptr);
            let blk = e.alloc(&Val::int(mem_layout(&leaves).size.max(1) as i64));
            e.clone_at(ty, &src, &blk);
            e.b.ret(Some(&blk));
        }
        Glue::SlotDrop => {
            e.drop_at(ty, &a(0, LTy::Ptr));
            e.b.ret(None);
        }
        Glue::SlotCopy => {
            e.clone_at(ty, &a(0, LTy::Ptr), &a(1, LTy::Ptr));
            e.b.ret(None);
        }
        Glue::CleanupThunk(f) => {
            let pty = e.g.m.funcs[f as usize].params[0].ty;
            let pl = e.g.lay.leaves(pty);
            let vs = load_leaves(&mut e.b, &a(0, LTy::Ptr), &pl, None);
            call_func(&mut e, f as usize, &vs);
            e.b.ret(None);
        }
        _ => unreachable!("supports rejects other glue"),
    }
    let (native_decls, native_data, native_body) = (e.decls, e.data, e.b.finish());
    Emitted {
        ret: sig.ret_text(),
        params: sig.formals(true),
        attrs: " nounwind".into(),
        decls: native_decls,
        data: native_data,
        consts: Vec::new(),
        body: native_body,
    }
}

/// `@"sym"` with the leaf signature, forwarding to `@"sym.n"`.
pub fn thunk(g: &Gen, kind: Glue, ty: Ty, sym: &str, types: &Types, loc: usize) -> Emitted {
    let leaves = &g.lay.leaves(ty);
    let mut b = FnBuilder::new(types, Some(loc));
    b.label("entry");
    let leaf = leaf_sig(kind, leaves);
    let nat = native_sig(kind, leaves);
    let n = native(sym);
    let a = |i: usize, t: &LTy| Val::new(format!("%a{i}"), t.clone());
    let args: Vec<Val> = leaf
        .params
        .iter()
        .enumerate()
        .map(|(i, p)| a(i, &p.ty))
        .collect();
    let mut fwd: Vec<(Val, &str)> = Vec::new();
    let mut sret = None;
    match kind {
        Glue::Drop | Glue::Clone if indirect(leaves) => {
            if kind == Glue::Clone {
                let out = b.alloca(&slot_ty(leaves));
                fwd.push((out.clone(), ""));
                sret = Some(out);
            }
            let slot = b.alloca(&slot_ty(leaves));
            store_leaves(&mut b, &slot, leaves, &args);
            fwd.push((slot, ""));
        }
        Glue::Drop | Glue::Clone => fwd = reg_args(&args, leaves),
        _ => {
            for v in &args {
                fwd.push((b.inttoptr(v), ""));
            }
        }
    }
    let decls = vec![nat.declare(&n)];
    let ret_value = match (&sret, &nat.ret) {
        (Some(out), _) => {
            b.call(&LTy::Void, "", &n, &fwd);
            Some(load_leaves(&mut b, out, leaves, None))
        }
        (None, LTy::Void) => {
            b.call(&LTy::Void, "", &n, &fwd);
            None
        }
        (None, LTy::Ptr) => {
            let p = b.call(&LTy::Ptr, nat.ret_attr, &n, &fwd).expect("result");
            Some(vec![b.ptrtoint(&p)])
        }
        (None, LTy::Tuple(fs)) => {
            let t = b.call(&nat.ret, "", &n, &fwd).expect("a tuple");
            Some((0..fs.len()).map(|k| b.extract(&t, k)).collect())
        }
        (None, _) => Some(vec![
            b.call(&nat.ret, nat.ret_attr, &n, &fwd).expect("result"),
        ]),
    };
    match ret_value.as_deref() {
        None | Some([]) => b.ret(None),
        Some([one]) => b.ret(Some(one)),
        Some(many) => b.ret_multi(many),
    }
    Emitted {
        ret: leaf.ret_text(),
        params: leaf.formals(true),
        attrs: " nounwind".into(),
        decls,
        data: Vec::new(),
        consts: Vec::new(),
        body: b.finish(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A string clone splits the block: the shared case skips the copy, and the two leaves leave
    /// as phis over the entry and the copy block.
    #[test]
    fn string_clone_joins_with_phis_over_both_paths() {
        let types = Types::default();
        let mut b = FnBuilder::new(&types, None);
        b.label("b0");
        let vs = vec![Val::new("%a0", LTy::I64), Val::new("%a1", LTy::I64)];
        let mut decls = Vec::new();
        let out = clone_str(&mut b, &mut decls, ("b0", "b0.d1", "b0.j1"), &vs, None);
        b.ret_multi(&out);
        let text = b.finish();
        assert!(text.contains("lshr i64 %a1, 62"), "{text}");
        assert!(text.contains("b0.d1:"), "{text}");
        assert!(text.contains("b0.j1:"), "{text}");
        assert!(text.contains("[ %a0, %b0 ], [ %v"), "{text}");
        assert!(text.contains(", %b0.d1 ]"), "{text}");
        assert_eq!(decls.len(), 1);
    }
}
