//! Interface values and method calls.
//!
//! An interface is two `i64` leaves: the data pointer and the vtable address with two tag bits
//! (`ms_rt_abi` explains them: 1 frees the box, 2 only calls and drops, 0 static). `iface.new`
//! and `iface.borrow` box the payload as one typed block (a heap block, or an `alloca` when the
//! value cannot leave the frame), the vtable address is a constant, and `call.method` loads the
//! slot and calls through it. When the box is built in the same function, LLVM sees the constant
//! vtable and the stack slot, so it can devirtualize the call and remove the box.

use super::{Cx, Out, leaves};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Module, Op};

/// Tag bit of a borrowed box whose leaves live in the frame: nothing is freed.
const FRAMED: i64 = 2;
/// Tag bit of a box on the heap, freed with the value.
const BOXED: i64 = 1;
/// Mask of the tag bits.
const TAG_MASK: i64 = !3;

/// Whether every leaf of the payload is stored as one of the three plain machine types.
fn plain_leaves(lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    lay.leaves(f.ty(inst.args[0]))
        .iter()
        .all(|l| matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8))
}

/// Whether `inst` is an interface operation this module emits.
pub fn handles(op: Op) -> bool {
    matches!(
        op,
        Op::IfaceNew
            | Op::IfaceBorrow
            | Op::IfaceView
            | Op::IfaceData
            | Op::IfaceIs
            | Op::CallMethod
    )
}

/// Whether the operands and result of `inst` have shapes this module can emit.
pub fn supported(m: &Module, lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    match inst.op {
        Op::IfaceNew | Op::IfaceBorrow => plain_leaves(lay, f, inst),
        Op::CallMethod => {
            let Imm::Method(iface, k) = inst.imm else {
                return false;
            };
            let sig = &m.ifaces[iface.index()].methods[k as usize];
            sig.params
                .iter()
                .chain([&sig.ret])
                .all(|t| super::supported_ty(lay, *t))
        }
        _ => true,
    }
}

/// The values of a result that shares leaves with its operand, if `op` is one: `iface.data` is
/// the data word, a view keeps it and retags the vtable word, which the instruction defines.
pub fn result_vals(op: Op, arg: &[Val], b: &mut FnBuilder) -> Option<Vec<Val>> {
    match op {
        Op::IfaceData => Some(vec![arg[0].clone()]),
        Op::IfaceView => Some(vec![arg[0].clone(), b.reserve(LTy::I64)]),
        _ => None,
    }
}

fn vtable_addr(cx: &Cx, out: &mut Out, inst: &Inst, b: &mut FnBuilder) -> Val {
    let Imm::Vtable(vt) = inst.imm else {
        unreachable!("an interface op carries its vtable")
    };
    let sym = &cx.plan.vtable[&vt.index()];
    out.data.push(sym.clone());
    let addr = Val::new(format!("@\"{sym}\""), LTy::Ptr);
    b.ptrtoint(&addr)
}

/// Stores the payload's leaves into `block`, each at its offset in the shared leaf layout.
fn store_payload(
    lay: &Layouts,
    ty: ms_mir::types::Ty,
    vals: &[Val],
    block: &Val,
    b: &mut FnBuilder,
) {
    let ls = lay.leaves(ty);
    let mem = mem_layout(&ls);
    for ((leaf, off), v) in ls.iter().zip(&mem.offsets).zip(vals) {
        let at = if *off == 0 {
            block.clone()
        } else {
            b.gep_bytes(block, *off as u64)
        };
        b.store(v, &at, leaf.size() as u64);
    }
}

/// A block of `payload` for a box: a fresh heap block, or a frame slot.
fn payload_block(
    lay: &Layouts,
    ty: ms_mir::types::Ty,
    framed: bool,
    out: &mut Out,
    b: &mut FnBuilder,
) -> Val {
    let ls = lay.leaves(ty);
    let size = mem_layout(&ls).size.max(8) as i64;
    if framed {
        // The same frame slot the Cranelift lowering makes: size rounded up to a word.
        let words = LTy::Array(Box::new(LTy::I64), (size as u64).div_ceil(8));
        return b.alloca(&words);
    }
    out.decls.push((
        "msrt_alloc".into(),
        "declare noalias align 16 ptr @\"msrt_alloc\"(i64)".into(),
    ));
    b.call(
        &LTy::Ptr,
        "noalias align 16 ",
        "msrt_alloc",
        &[(Val::int(size), "")],
    )
    .expect("alloc returns a pointer")
}

/// Emits `inst`; an `iface.borrow` result in `cx.framed` stays in the frame.
pub fn emit(cx: &Cx, inst: &Inst, out: &mut Out, b: &mut FnBuilder) {
    let Cx {
        m, lay, f, vals, ..
    } = *cx;
    let framed = inst.res.is_some_and(|r| cx.framed.contains(&r.index()));
    let arg = |i: usize| vals[&inst.args[i].index()].clone();
    let res = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    match inst.op {
        Op::IfaceNew | Op::IfaceBorrow => {
            let ty = f.ty(inst.args[0]);
            let on_heap = inst.op == Op::IfaceNew || !framed;
            let block = payload_block(lay, ty, !on_heap, out, b);
            store_payload(lay, ty, &arg(0), &block, b);
            let tag = match (inst.op, framed) {
                (Op::IfaceNew, _) => 0,
                (_, true) => FRAMED,
                (_, false) => BOXED,
            };
            b.name_next(&res[0]);
            b.ptrtoint(&block);
            if tag == 0 {
                // A static vtable: the address is the whole word.
                b.name_next(&res[1]);
                vtable_addr(cx, out, inst, b);
            } else {
                let vt = vtable_addr(cx, out, inst, b);
                b.name_next(&res[1]);
                b.bin(Bin::Or, &vt, &Val::int(tag));
            }
        }
        Op::IfaceView => {
            // The same data with the vtable retagged as a view: nothing is freed.
            let v = arg(0);
            let bare = b.bin(Bin::And, &v[1], &Val::int(TAG_MASK));
            b.name_next(&res[1]);
            b.bin(Bin::Or, &bare, &Val::int(FRAMED));
        }
        Op::IfaceData => {}
        Op::IfaceIs => {
            let have = b.bin(Bin::And, &arg(0)[1], &Val::int(TAG_MASK));
            let want = vtable_addr(cx, out, inst, b);
            let c = b.icmp("eq", &have, &want);
            b.name_next(&res[0]);
            b.zext(&c, LTy::I8);
        }
        Op::CallMethod => {
            let Imm::Method(iface, k) = inst.imm else {
                unreachable!()
            };
            let sig = &m.ifaces[iface.index()].methods[k as usize];
            let recv = arg(0);
            let bare = b.bin(Bin::And, &recv[1], &Val::int(TAG_MASK));
            let table = b.inttoptr(&bare);
            let slot = b.gep_bytes(&table, 8 * (1 + k as u64));
            // Vtables are constant, so the slot may be hoisted out of loops.
            let code = b.load_invariant(&LTy::Ptr, &slot, 8);
            let mut args: Vec<(Val, &str)> = vec![(recv[0].clone(), "")];
            for (p, a) in sig.params.iter().zip(&inst.args[1..]) {
                for (v, (_, at)) in vals[&a.index()].iter().zip(leaves(lay, *p)) {
                    args.push((v.clone(), at));
                }
            }
            let ret = super::ret_ty(lay, sig.ret);
            let attr = super::ret_attr(lay, sig.ret);
            if res.len() <= 1 {
                if let [r] = res.as_slice() {
                    b.name_next(r);
                }
                b.call_ptr(&ret, attr, &code, &args);
            } else {
                let t = b
                    .call_ptr(&ret, attr, &code, &args)
                    .expect("a tuple result");
                for (k, dst) in res.iter().enumerate() {
                    b.name_next(dst);
                    b.extract(&t, k);
                }
            }
        }
        _ => unreachable!("handles() lists the interface ops"),
    }
}

#[cfg(test)]
mod tests {
    use super::super::{Plan, emit, supports};
    use crate::layout::Layouts;

    const SRC: &str = r#"module "iface"
iface Area { area(int) -> int }
vtable @v_int: Area for int { @area_int }
entry @main
fn @area_int(%self: ptr, %k: int) -> int method {
b0:
  ret %k
}
fn @build(%x: int, %k: int) -> int {
b0:
  %s: dyn Area = iface.new @v_int %x
  %b: dyn Area = iface.borrow @v_int %x
  %v: dyn Area = iface.view %b
  %p: ptr = iface.data %v
  %is: bool = iface.is @v_int %v
  %r: int = call.method Area.area (%s, %k)
  ret %r
}
fn @main() -> int {
b0:
  %x: int = iconst 1
  ret %x
}
"#;

    /// A box is one typed block: a heap block for `iface.new` (tag 0), a frame slot for a borrow
    /// that stays in the frame (tag 2), the vtable address is a constant, a view retags it, a
    /// method call loads the slot with a hoistable load.
    #[test]
    fn boxes_views_and_method_calls_are_typed() {
        let m = ms_mir::parse::parse_module(SRC).expect("parse");
        let lay = Layouts::new(&m);
        let f = m.funcs.iter().find(|f| f.name == "build").expect("build");
        assert!(supports(&m, &lay, f));
        let mut plan = Plan::default();
        plan.vtable.insert(0, "vt0".into());
        let out = emit(&m, &lay, f, &plan, 0, &|i| format!("f{i}"));
        let ir = &out.body;
        assert!(
            ir.contains("call noalias align 16 ptr @\"msrt_alloc\"(i64 8)"),
            "{ir}"
        );
        assert!(ir.contains("store i64 %a0_0, ptr"), "{ir}");
        assert!(ir.contains("ptrtoint ptr @\"vt0\" to i64"), "{ir}");
        // `iface.borrow` is not framed here (its result is viewed), so it is a heap box tagged 1.
        assert!(ir.contains("or i64 %v") && ir.contains(", 1"), "{ir}");
        assert!(ir.contains("and i64 %v") && ir.contains(", -4"), "{ir}");
        assert!(ir.contains("or i64 %v") && ir.contains(", 2"), "{ir}");
        assert!(ir.contains("icmp eq i64"), "{ir}");
        assert!(ir.contains("!invariant.load"), "{ir}");
        assert!(ir.contains("call i64 %v"), "{ir}");
        assert_eq!(out.data, ["vt0", "vt0", "vt0"]);
    }
}
