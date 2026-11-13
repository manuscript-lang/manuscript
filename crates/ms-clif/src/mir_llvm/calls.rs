//! Calls: direct calls between functions emitted from MIR, and calls to runtime functions.
//!
//! A call to a runtime function follows the calling convention of the Cranelift lowering: a value
//! that is a single register-sized word (or a handful of them) passes by leaves, anything else
//! passes the address of a copy, and a result that does not pass by leaves comes back through a
//! hidden last argument.

use super::attrs::pure_attrs;
use super::{Area, Cx, Vals, leaves, ret_attr, ret_ty, supported_ty};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{ExternDef, Func, Imm, Inst, Mode, Module, Op};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    inst_ok,
    emit,
    ..Area::NONE
};

fn handles(op: Op) -> bool {
    matches!(op, Op::Call | Op::CallRt)
}

/// A runtime call needs value types the emitter holds, and no special role or C shim.
fn inst_ok(m: &Module, lay: &Layouts, _: &Func, i: &Inst) -> bool {
    let Imm::Ext(e) = i.imm else {
        return i.op != Op::CallRt;
    };
    let def = &m.externs[e.index()];
    def.params.iter().all(|p| supported_ty(lay, p.ty))
        && supported_ty(lay, def.ret)
        && extern_ok(m, def)
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    if let (Op::CallRt, Imm::Ext(e)) = (inst.op, inst.imm) {
        let out: Vec<Val> = inst
            .res
            .map(|r| vals[&r.index()].clone())
            .unwrap_or_default();
        let def = cx.m.externs[e.index()].clone();
        return call_extern(cx, inst, vals, &def, &out, b);
    }
    direct_call(cx, inst, vals, b);
}

/// Whether `def` is a runtime function this module can call.
fn extern_ok(m: &Module, def: &ExternDef) -> bool {
    use ms_mir::ir::ExternRole::{CleanupDiscard, MapNew};
    !m.c_externs.contains(&def.name) && !matches!(def.role, CleanupDiscard | MapNew)
}

/// Whether a value of `ty` passes to a runtime function as its leaves (otherwise by address).
pub(super) fn passes_directly(lay: &Layouts, ty: Ty) -> bool {
    match lay.m.types.kind(ty) {
        TyKind::Unit
        | TyKind::Bool
        | TyKind::Int
        | TyKind::Int8
        | TyKind::Int16
        | TyKind::Int32
        | TyKind::UInt8
        | TyKind::UInt16
        | TyKind::UInt32
        | TyKind::UInt64
        | TyKind::Float
        | TyKind::Float32
        | TyKind::Ptr
        | TyKind::Fn(..)
        | TyKind::Iface(_) => true,
        TyKind::Obj(n, _) => !n.is_map_or_set(),
        TyKind::Opt(inner) => lay.opt_is_nullable(*inner) || lay.m.types.is_scalar(*inner),
        _ => false,
    }
}

/// The memory type of a leaf.
pub(super) fn mem_ty(l: Leaf) -> LTy {
    match l {
        Leaf::I64 => LTy::I64,
        Leaf::F64 => LTy::F64,
        Leaf::I8 | Leaf::N8 | Leaf::U8 => LTy::I8,
        Leaf::N16 | Leaf::U16 => LTy::I16,
        Leaf::N32 | Leaf::U32 => LTy::I32,
        Leaf::F32 => LTy::F32,
    }
}

/// A struct that holds values in memory: some header fields, then parts (a closure's captures, one
/// spilled argument) whose leaves sit where `mem_layout` puts them, with the padding spelled out.
/// Accesses are `getelementptr` on the struct and typed loads and stores, so LLVM sees fields
/// instead of byte offsets. The offsets agree with the runtime and the translation by construction
/// (`debug_assert`ed against the size `mem_layout` gives).
pub(super) struct MemObj {
    pub ty: LTy,
    /// The struct field of each leaf, per part.
    fields: Vec<Vec<usize>>,
    /// Size in bytes.
    pub size: u64,
}

impl MemObj {
    /// `header` types come first; each part starts at a multiple of its alignment, and the whole
    /// is rounded up to `round` bytes.
    pub(super) fn new(header: &[LTy], parts: &[Vec<Leaf>], round: u64) -> MemObj {
        let types = crate::llvm_build::Types::default();
        let mut fields: Vec<LTy> = header.to_vec();
        let mut off: u64 = header.iter().map(|t| types.size_align(t).0).sum();
        let mut index = Vec::new();
        let pad = |fields: &mut Vec<LTy>, n: u64| {
            if n > 0 {
                fields.push(LTy::Array(Box::new(LTy::I8), n));
            }
        };
        for leaves in parts {
            let l = mem_layout(leaves);
            let start = off.next_multiple_of(u64::from(l.align));
            pad(&mut fields, start - off);
            off = start;
            let mut own = Vec::new();
            for (leaf, at) in leaves.iter().zip(&l.offsets) {
                let at = start + u64::from(*at);
                pad(&mut fields, at - off);
                own.push(fields.len());
                fields.push(mem_ty(*leaf));
                off = at + u64::from(leaf.size());
            }
            let end = start + u64::from(l.size);
            pad(&mut fields, end - off);
            off = end;
            index.push(own);
        }
        let size = off.next_multiple_of(round.max(1));
        pad(&mut fields, size - off);
        let ty = LTy::Tuple(fields);
        debug_assert_eq!(types.size_align(&ty).0, size);
        MemObj {
            ty,
            fields: index,
            size,
        }
    }

    /// The address of capture `part`'s first leaf.
    pub(super) fn field_of(&self, b: &mut FnBuilder, base: &Val, part: usize) -> Val {
        b.field_ptr(&self.ty, base, self.fields[part][0])
    }

    /// Stores the register leaves `vs` of part `part` into the object at `base`.
    pub(super) fn store(
        &self,
        b: &mut FnBuilder,
        base: &Val,
        part: usize,
        leaves: &[Leaf],
        vs: &[Val],
    ) {
        for ((l, v), idx) in leaves.iter().zip(vs).zip(&self.fields[part]) {
            let p = b.field_ptr(&self.ty, base, *idx);
            let v = match l {
                Leaf::N8 | Leaf::U8 | Leaf::N16 | Leaf::U16 | Leaf::N32 | Leaf::U32 => {
                    b.trunc(v, mem_ty(*l))
                }
                Leaf::F32 => b.fptrunc(v, LTy::F32),
                _ => v.clone(),
            };
            b.store(&v, &p, u64::from(l.size()));
        }
    }

    /// Loads part `part` from the object at `base` into the registers `dst` (each takes the name
    /// reserved for it).
    pub(super) fn load(
        &self,
        b: &mut FnBuilder,
        base: &Val,
        part: usize,
        leaves: &[Leaf],
        dst: &[Val],
    ) {
        for ((l, d), idx) in leaves.iter().zip(dst).zip(&self.fields[part]) {
            let p = b.field_ptr(&self.ty, base, *idx);
            let align = u64::from(l.size());
            match l {
                Leaf::I64 | Leaf::F64 | Leaf::I8 => {
                    b.name_next(d);
                    b.load(&mem_ty(*l), &p, align);
                }
                Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => {
                    let v = b.load(&mem_ty(*l), &p, align);
                    b.name_next(d);
                    if matches!(l, Leaf::N8 | Leaf::N16 | Leaf::N32) {
                        b.sext(&v, LTy::I64);
                    } else {
                        b.zext(&v, LTy::I64);
                    }
                }
                Leaf::F32 => {
                    let v = b.load(&LTy::F32, &p, 4);
                    b.name_next(d);
                    b.fpext(&v, LTy::F64);
                }
            }
        }
    }
}

/// `declare` text of a function with these leaf parameters and result.
pub(super) fn declare_text(sym: &str, ret: &(LTy, &str), params: &[(LTy, &str)]) -> String {
    let t = |ty: &LTy| crate::llvm_build::Types::default().text(ty);
    let formals: Vec<String> = params
        .iter()
        .map(|(ty, a)| format!("{}{a}", t(ty)))
        .collect();
    format!(
        "declare {}{} @\"{sym}\"({})",
        ret.1,
        t(&ret.0),
        formals.join(", ")
    )
}

/// The leaves of `ty` as `(register type, attribute)`.
pub(super) fn leaf_list(lay: &Layouts, ty: Ty) -> Vec<(LTy, &'static str)> {
    super::leaves(lay, ty)
}

/// The result of a call that returns `rets` leaves: `void`, the leaf, or a tuple, and its attribute.
pub(super) fn ret_of(rets: &[(LTy, &'static str)]) -> (LTy, &'static str) {
    match rets {
        [] => (LTy::Void, ""),
        [(t, a)] => (t.clone(), if a.is_empty() { "" } else { "zeroext " }),
        many => (LTy::Tuple(many.iter().map(|r| r.0.clone()).collect()), ""),
    }
}

/// Where a call goes.
pub(super) enum Callee<'a> {
    Symbol(&'a str),
    Pointer(&'a Val),
}

/// Writes a call and binds its result leaves to the reserved names `out`.
pub(super) fn call_into(
    b: &mut FnBuilder,
    callee: Callee,
    rets: &[(LTy, &'static str)],
    args: &[(Val, &str)],
    out: &[Val],
) {
    let (ret, attr) = ret_of(rets);
    let named = |b: &mut FnBuilder, v: &Val| b.name_next(v);
    if let [dst] = out {
        named(b, dst);
    }
    let r = match callee {
        Callee::Symbol(s) => b.call(&ret, attr, s, args),
        Callee::Pointer(p) => b.call_ptr(&ret, attr, p, args),
    };
    if out.len() > 1 {
        let t = r.expect("a tuple result");
        for (k, dst) in out.iter().enumerate() {
            b.name_next(dst);
            b.extract(&t, k);
        }
    }
}

/// The arguments of `inst` from index `from`, as leaves with the attributes of `params`.
pub(super) fn leaf_args(
    cx: &Cx,
    vals: &Vals,
    inst: &Inst,
    from: usize,
    params: &[Ty],
) -> Vec<(Val, &'static str)> {
    let mut args = Vec::new();
    for (p, a) in params.iter().zip(&inst.args[from..]) {
        for (v, (_, at)) in vals[&a.index()].iter().zip(leaf_list(cx.lay, *p)) {
            args.push((v.clone(), at));
        }
    }
    args
}

/// Declares the MIR function `callee` under `sym`.
pub(super) fn declare_function(cx: &mut Cx, sym: &str, callee: &Func) {
    let params: Vec<(LTy, &str)> = callee
        .params
        .iter()
        .flat_map(|p| leaf_list(cx.lay, p.ty))
        .collect();
    let ret = ret_of(&leaf_list(cx.lay, callee.ret));
    cx.decls
        .push((sym.to_string(), declare_text(sym, &ret, &params)));
}

/// A call to the runtime function `def`: leaves where the value passes directly, the address of a
/// copy otherwise, and a hidden last argument for a result that does not pass directly.
fn call_extern(
    cx: &mut Cx,
    inst: &Inst,
    vals: &Vals,
    def: &ExternDef,
    out: &[Val],
    b: &mut FnBuilder,
) {
    let lay = cx.lay;
    let mut formals: Vec<(LTy, &str)> = Vec::new();
    let mut args: Vec<(Val, &str)> = Vec::new();
    let mut temps: Vec<(Val, u64)> = Vec::new();
    for (p, a) in def.params.iter().zip(&inst.args) {
        let vs = &vals[&a.index()];
        if passes_directly(lay, p.ty) {
            for (v, (t, at)) in vs.iter().zip(leaf_list(lay, p.ty)) {
                formals.push((t, at));
                args.push((v.clone(), at));
            }
        } else {
            // The callee gets the address of a copy; it only reads a borrowed one.
            let leaves = lay.leaves(p.ty);
            let obj = MemObj::new(&[], std::slice::from_ref(&leaves), 1);
            let slot = b.alloca(&obj.ty);
            b.lifetime_start(&slot, obj.size);
            obj.store(b, &slot, 0, &leaves, vs);
            temps.push((slot.clone(), obj.size));
            formals.push((
                LTy::Ptr,
                if p.mode == Mode::Borrow {
                    BORROWED
                } else {
                    KEPT
                },
            ));
            args.push((
                slot,
                if p.mode == Mode::Borrow {
                    BORROWED
                } else {
                    KEPT
                },
            ));
        }
    }
    let direct_ret = passes_directly(lay, def.ret);
    let rets = if direct_ret {
        leaf_list(lay, def.ret)
    } else {
        Vec::new()
    };
    let mut result_slot = None;
    if !direct_ret {
        // The result comes back through a hidden last argument, a slot the callee fills.
        let leaves = lay.leaves(def.ret);
        let obj = MemObj::new(&[], std::slice::from_ref(&leaves), 1);
        let slot = b.alloca(&obj.ty);
        b.lifetime_start(&slot, obj.size);
        formals.push((LTy::Ptr, OUT));
        args.push((slot.clone(), OUT));
        result_slot = Some((slot, leaves, obj));
    }
    let attrs = crate::llvm_ir::runtime_attrs(&def.name, def.reads);
    let ret = ret_of(&rets);
    if crate::llvm_ir::returns_fresh_block(&def.name) {
        // An allocator hands back a block nothing else reaches; the result is its address.
        cx.decls.push((
            def.name.clone(),
            format!(
                "declare noalias align 16 ptr @\"{}\"({}){attrs}",
                def.name,
                param_text(&formals)
            ),
        ));
        let p = b
            .call(&LTy::Ptr, "noalias align 16 ", &def.name, &args)
            .expect("a pointer");
        b.name_next(&out[0]);
        b.ptrtoint(&p);
    } else {
        cx.decls.push((
            def.name.clone(),
            format!(
                "declare {}{} @\"{}\"({}){attrs}",
                ret.1,
                crate::llvm_build::Types::default().text(&ret.0),
                def.name,
                param_text(&formals)
            ),
        ));
        // A result that comes back through the hidden pointer is loaded below.
        call_into(
            b,
            Callee::Symbol(&def.name),
            &rets,
            &args,
            if direct_ret { out } else { &[] },
        );
    }
    if let Some((slot, leaves, obj)) = result_slot {
        obj.load(b, &slot, 0, &leaves, out);
        b.lifetime_end(&slot, obj.size);
    }
    for (slot, size) in temps {
        b.lifetime_end(&slot, size);
    }
}

/// Attributes of a pointer argument: a copy the callee only reads and does not keep, one it may
/// take over, and the slot it fills.
const BORROWED: &str = " readonly captures(none)";
const KEPT: &str = " captures(none)";
const OUT: &str = " noalias writeonly captures(none)";

fn param_text(formals: &[(LTy, &str)]) -> String {
    let t = crate::llvm_build::Types::default();
    formals
        .iter()
        .map(|(ty, a)| format!("{}{a}", t.text(ty)))
        .collect::<Vec<_>>()
        .join(", ")
}

fn direct_call(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    // A single-leaf result is named in place.
    if let [r] = out.as_slice() {
        b.name_next(r);
    }
    let Imm::Func(c) = inst.imm else { return };
    let callee = &m.funcs[c.index()];
    let sym = (cx.symbol_of)(c.index());
    let ret = ret_ty(lay, callee.ret);
    let attr = ret_attr(lay, callee.ret);
    let mut args: Vec<(Val, &str)> = Vec::new();
    for (p, a) in callee.params.iter().zip(&inst.args) {
        for (v, (_, at)) in vals[&a.index()].iter().zip(leaves(lay, p.ty)) {
            args.push((v.clone(), at));
        }
    }
    let formals: Vec<String> = args
        .iter()
        .map(|(v, a)| format!("{}{a}", Types::default().text(&v.ty)))
        .collect();
    cx.decls.push((
        sym.clone(),
        format!(
            "declare {attr}{} @\"{sym}\"({}){}",
            Types::default().text(&ret),
            formals.join(", "),
            pure_attrs(m, lay, c.index(), &mut cx.memo).unwrap_or("")
        ),
    ));
    if out.len() <= 1 {
        b.call(&ret, attr, &sym, &args);
    } else {
        let t = b.call(&ret, attr, &sym, &args).expect("a tuple result");
        for (k, dst) in out.iter().enumerate() {
            b.name_next(dst);
            b.extract(&t, k);
        }
    }
}
