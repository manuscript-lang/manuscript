//! Closures, indirect calls and runtime calls for the direct emitter.
//!
//! A closure is one heap or frame object: `{ clone, drop, code, captures.. }` (see
//! `ms_rt_abi::Closure`), with the captures laid out like a record of their leaves. Its value is
//! the object's address, so a closure travels as one `i64` leaf and an indirect call loads the
//! code pointer from the object and passes the object as the first argument. A call to a runtime
//! function follows the calling convention of the Cranelift lowering: a value that is a single
//! register-sized word (or a handful of them) passes by leaves, anything else passes the address
//! of a copy, and a result that does not pass by leaves comes back through a hidden last argument.

use super::{Cx, Out};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{ExternDef, Func, Imm, Inst, Module, Op};
use ms_mir::types::{Ty, TyKind};

/// The ops this module writes.
pub fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::ClosureNew
            | Op::ClosureCap
            | Op::ClosureCapAddr
            | Op::CallInd
            | Op::CallRt
            | Op::FuncAddr
    )
}

/// Whether `def` is a runtime function this module can call.
pub fn extern_ok(m: &Module, def: &ExternDef) -> bool {
    use ms_mir::ir::ExternRole::{CleanupDiscard, MapNew};
    !m.c_externs.contains(&def.name) && !matches!(def.role, CleanupDiscard | MapNew)
}

/// Whether a value of `ty` passes to a runtime function as its leaves (otherwise by address).
pub fn passes_directly(lay: &Layouts, ty: Ty) -> bool {
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
fn mem_ty(l: Leaf) -> LTy {
    match l {
        Leaf::I64 => LTy::I64,
        Leaf::F64 => LTy::F64,
        Leaf::I8 | Leaf::N8 | Leaf::U8 => LTy::I8,
        Leaf::N16 | Leaf::U16 => LTy::I16,
        Leaf::N32 | Leaf::U32 => LTy::I32,
        Leaf::F32 => LTy::F32,
    }
}

/// Stores the leaves `vs` into the object at `base`, from byte `at`, as `mem_layout` places them.
fn store_leaves(b: &mut FnBuilder, base: &Val, at: u64, leaves: &[Leaf], vs: &[Val]) {
    let lay = mem_layout(leaves);
    for ((l, v), off) in leaves.iter().zip(vs).zip(&lay.offsets) {
        let p = b.gep_bytes(base, at + u64::from(*off));
        let narrow = match l {
            Leaf::N8 | Leaf::U8 => Some(LTy::I8),
            Leaf::N16 | Leaf::U16 => Some(LTy::I16),
            Leaf::N32 | Leaf::U32 => Some(LTy::I32),
            _ => None,
        };
        let v = match (narrow, l) {
            (Some(t), _) => b.trunc(v, t),
            (None, Leaf::F32) => b.fptrunc(v, LTy::F32),
            (None, _) => v.clone(),
        };
        b.store(&v, &p, u64::from(l.size()));
    }
}

/// Loads the leaves of a value from the object at `base`, from byte `at`, into the registers
/// `dst` (each takes the name reserved for it).
fn load_leaves(b: &mut FnBuilder, base: &Val, at: u64, leaves: &[Leaf], dst: &[Val]) {
    let lay = mem_layout(leaves);
    for ((l, d), off) in leaves.iter().zip(dst).zip(&lay.offsets) {
        let p = b.gep_bytes(base, at + u64::from(*off));
        match l {
            Leaf::I64 | Leaf::F64 | Leaf::I8 => {
                b.name_next(d);
                b.load(&mem_ty(*l), &p, u64::from(l.size()));
            }
            Leaf::N8 | Leaf::N16 | Leaf::N32 | Leaf::U8 | Leaf::U16 | Leaf::U32 => {
                let v = b.load(&mem_ty(*l), &p, u64::from(l.size()));
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

/// The byte offset and leaves of capture `i` in a closure with `captures`, and the object size.
pub fn capture_layout(lay: &Layouts, captures: &[Ty], i: usize) -> (u64, Vec<Leaf>) {
    let mut off = u64::from(crate::cg::CLOSURE_CAPTURES);
    for (k, c) in captures.iter().enumerate() {
        let leaves = lay.leaves(*c);
        let l = mem_layout(&leaves);
        off = off.next_multiple_of(u64::from(l.align));
        if k == i {
            return (off, leaves);
        }
        off += u64::from(l.size);
    }
    unreachable!("capture {i} of {}", captures.len())
}

/// The size of a closure object with `captures`, rounded to a word.
fn object_size(lay: &Layouts, captures: &[Ty]) -> u64 {
    let mut off = u64::from(crate::cg::CLOSURE_CAPTURES);
    for c in captures {
        let l = mem_layout(&lay.leaves(*c));
        off = off.next_multiple_of(u64::from(l.align)) + u64::from(l.size);
    }
    off.next_multiple_of(8)
}

/// `declare` text of a function with these leaf parameters and result.
fn declare_text(sym: &str, ret: &(LTy, &str), params: &[(LTy, &str)]) -> String {
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
fn leaf_list(lay: &Layouts, ty: Ty) -> Vec<(LTy, &'static str)> {
    super::leaves(lay, ty)
}

/// The result of a call that returns `rets` leaves: `void`, the leaf, or a tuple, and its attribute.
fn ret_of(rets: &[(LTy, &'static str)]) -> (LTy, &'static str) {
    match rets {
        [] => (LTy::Void, ""),
        [(t, a)] => (t.clone(), if a.is_empty() { "" } else { "zeroext " }),
        many => (LTy::Tuple(many.iter().map(|r| r.0.clone()).collect()), ""),
    }
}

/// Where a call goes.
enum Callee<'a> {
    Symbol(&'a str),
    Pointer(&'a Val),
}

/// Writes a call and binds its result leaves to the reserved names `out`.
fn call_into(
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
fn leaf_args(cx: &Cx, inst: &Inst, from: usize, params: &[Ty]) -> Vec<(Val, &'static str)> {
    let mut args = Vec::new();
    for (p, a) in params.iter().zip(&inst.args[from..]) {
        for (v, (_, at)) in cx.vals[&a.index()].iter().zip(leaf_list(cx.lay, *p)) {
            args.push((v.clone(), at));
        }
    }
    args
}

/// Writes `inst`, one of [`handles`]'s ops.
pub fn emit(cx: &Cx, inst: &Inst, sinks: &mut Out, b: &mut FnBuilder) {
    let Cx {
        m, lay, f, vals, ..
    } = *cx;
    let out: Vec<Val> = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    match (inst.op, inst.imm) {
        (Op::ClosureNew, Imm::Func(c)) => closure_new(cx, inst, c.index(), &out, sinks, b),
        (Op::ClosureCap | Op::ClosureCapAddr, Imm::Idx(i)) => {
            let ms_mir::ir::FuncKind::Closure { captures } = &f.kind else {
                unreachable!("closure.cap outside a closure")
            };
            let (off, leaves) = capture_layout(lay, captures, i as usize);
            let env = &vals[&inst.args[0].index()][0];
            if inst.op == Op::ClosureCapAddr {
                b.name_next(&out[0]);
                b.bin(crate::llvm_build::Bin::Add, env, &Val::int(off as i64));
            } else {
                let base = b.inttoptr(env);
                load_leaves(b, &base, off, &leaves, &out);
            }
        }
        (Op::FuncAddr, Imm::Func(c)) => {
            let sym = (cx.symbol_of)(c.index());
            let callee = &m.funcs[c.index()];
            declare_function(cx, &mut sinks.decls, &sym, callee);
            let addr = Val::new(format!("@\"{sym}\""), LTy::Ptr);
            b.name_next(&out[0]);
            b.ptrtoint(&addr);
        }
        (Op::CallInd, _) => {
            let TyKind::Fn(ps, r) = lay.m.types.kind(f.ty(inst.args[0])).clone() else {
                unreachable!("call.ind of a non-closure")
            };
            let clo = vals[&inst.args[0].index()][0].clone();
            let obj = b.inttoptr(&clo);
            let at = b.gep_bytes(&obj, u64::from(crate::cg::CLOSURE_CODE as u32));
            let code = b.load(&LTy::Ptr, &at, 8);
            let mut args = vec![(clo, "")];
            args.extend(leaf_args(cx, inst, 1, &ps));
            call_into(b, Callee::Pointer(&code), &leaf_list(lay, r), &args, &out);
        }
        (Op::CallRt, Imm::Ext(e)) => call_extern(cx, inst, &m.externs[e.index()], &out, sinks, b),
        _ => unreachable!("handles accepts only closure and call ops"),
    }
}

/// Declares the MIR function `callee` under `sym`.
fn declare_function(cx: &Cx, decls: &mut Vec<(String, String)>, sym: &str, callee: &Func) {
    let params: Vec<(LTy, &str)> = callee
        .params
        .iter()
        .flat_map(|p| leaf_list(cx.lay, p.ty))
        .collect();
    let ret = ret_of(&leaf_list(cx.lay, callee.ret));
    decls.push((sym.to_string(), declare_text(sym, &ret, &params)));
}

fn closure_new(cx: &Cx, inst: &Inst, c: usize, out: &[Val], sinks: &mut Out, b: &mut FnBuilder) {
    let Cx {
        m,
        lay,
        plan,
        vals,
        symbol_of,
        ..
    } = *cx;
    let callee = &m.funcs[c];
    let captures = match &callee.kind {
        ms_mir::ir::FuncKind::Closure { captures } => captures.clone(),
        _ => Vec::new(),
    };
    let size = object_size(lay, &captures);
    let framed = inst.res.is_some_and(|r| plan.framed.contains(&r.index()));
    // The object is the address of a frame slot, or a fresh heap block.
    let obj = if framed {
        b.alloca(&LTy::Array(Box::new(LTy::I64), size / 8))
    } else {
        sinks.decls.push((
            "msrt_alloc".into(),
            "declare noalias align 16 ptr @\"msrt_alloc\"(i64)".into(),
        ));
        b.call(
            &LTy::Ptr,
            "noalias align 16 ",
            "msrt_alloc",
            &[(Val::int(size.max(1) as i64), "")],
        )
        .expect("a pointer")
    };
    let syms = &plan.closures[&(c, framed)];
    sinks.decls.push((
        syms.clone.clone(),
        declare_text(&syms.clone, &(LTy::I64, ""), &[(LTy::I64, "")]),
    ));
    sinks.decls.push((
        syms.drop.clone(),
        declare_text(&syms.drop, &(LTy::Void, ""), &[(LTy::I64, "")]),
    ));
    let code = symbol_of(c);
    declare_function(cx, &mut sinks.decls, &code, callee);
    let header = [
        (0, syms.clone.as_str()),
        (8, syms.drop.as_str()),
        (u64::from(crate::cg::CLOSURE_CODE as u32), code.as_str()),
    ];
    for (at, sym) in header {
        let p = b.gep_bytes(&obj, at);
        b.store(&Val::new(format!("@\"{sym}\""), LTy::Ptr), &p, 8);
    }
    for (i, _) in captures.iter().enumerate() {
        let (off, leaves) = capture_layout(lay, &captures, i);
        store_leaves(b, &obj, off, &leaves, &vals[&inst.args[i].index()]);
    }
    b.name_next(&out[0]);
    b.ptrtoint(&obj);
}

/// A call to the runtime function `def`: leaves where the value passes directly, the address of a
/// copy otherwise, and a hidden last argument for a result that does not pass directly.
fn call_extern(
    cx: &Cx,
    inst: &Inst,
    def: &ExternDef,
    out: &[Val],
    sinks: &mut Out,
    b: &mut FnBuilder,
) {
    let Cx { lay, vals, .. } = *cx;
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
            let leaves = lay.leaves(p.ty);
            let slot = spill(b, &leaves, vs);
            temps.push((slot.clone(), u64::from(mem_layout(&leaves).size)));
            formals.push((LTy::I64, ""));
            args.push((b.ptrtoint(&slot), ""));
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
        let leaves = lay.leaves(def.ret);
        let size = u64::from(mem_layout(&leaves).size);
        let slot = b.alloca(&LTy::Array(Box::new(LTy::I64), size.div_ceil(8).max(1)));
        b.lifetime_start(&slot, size);
        formals.push((LTy::I64, ""));
        args.push((b.ptrtoint(&slot), ""));
        result_slot = Some((slot, leaves, size));
    }
    let attrs = crate::llvm_ir::runtime_attrs(&def.name, def.reads);
    let ret = ret_of(&rets);
    if crate::llvm_ir::returns_fresh_block(&def.name) {
        // An allocator hands back a block nothing else reaches; the result is its address.
        sinks.decls.push((
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
        sinks.decls.push((
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
    if let Some((slot, leaves, size)) = result_slot {
        load_leaves(b, &slot, 0, &leaves, out);
        b.lifetime_end(&slot, size);
    }
    for (slot, size) in temps {
        b.lifetime_end(&slot, size);
    }
}

fn param_text(formals: &[(LTy, &str)]) -> String {
    let t = crate::llvm_build::Types::default();
    formals
        .iter()
        .map(|(ty, a)| format!("{}{a}", t.text(ty)))
        .collect::<Vec<_>>()
        .join(", ")
}

/// A stack copy of the leaves `vs`, live from here until `lifetime_end`.
fn spill(b: &mut FnBuilder, leaves: &[Leaf], vs: &[Val]) -> Val {
    let size = u64::from(mem_layout(leaves).size);
    let slot = b.alloca(&LTy::Array(Box::new(LTy::I64), size.div_ceil(8).max(1)));
    b.lifetime_start(&slot, size);
    store_leaves(b, &slot, 0, leaves, vs);
    slot
}
