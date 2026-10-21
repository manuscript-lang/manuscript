//! The `slotfuse` pass: lets a runtime mutator work on its receiver in place.
//!
//! A mutating method on a field moves the receiver out, through a stack slot into the
//! runtime call, and back:
//!
//! ```text
//! a = take T p;  s = slot T;  put s, a;  call.rt f(s, ..);  b = take T s;  put p, b
//! ```
//!
//! Nothing runs between the move out and the move back, so the call can use `p` itself.
//! This removes two three-word copies and the slot from every `append`/`insert`/`add`.

use crate::ir::{Func, Inst, Module, Op, Value};

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for f in &mut m.funcs {
        changed |= fuse_func(f);
    }
    changed
}

fn fuse_func(f: &mut Func) -> bool {
    let mut uses = vec![0u32; f.values.len()];
    for b in &f.blocks {
        for i in &b.insts {
            for a in &i.args {
                uses[a.index()] += 1;
            }
        }
        b.term.for_each_use(|v| uses[v.index()] += 1);
    }
    let mut changed = false;
    for b in &mut f.blocks {
        let mut k = 0;
        while k + 6 <= b.insts.len() {
            if let Some(p) = matches_at(&b.insts[k..k + 6], &uses) {
                let s = b.insts[k + 1].res.expect("slot result");
                for a in &mut b.insts[k + 3].args {
                    if *a == s {
                        *a = p;
                    }
                }
                let call = b.insts[k + 3].clone();
                b.insts.splice(k..k + 6, [call]);
                changed = true;
            } else {
                k += 1;
            }
        }
    }
    changed
}

/// The receiver pointer when the six instructions are the move-out/call/move-back shape.
fn matches_at(w: &[Inst], uses: &[u32]) -> Option<Value> {
    let [take_out, slot, put_in, call, take_back, put_back] = w else {
        return None;
    };
    if take_out.op != Op::Take
        || slot.op != Op::Slot
        || put_in.op != Op::Put
        || call.op != Op::CallRt
        || take_back.op != Op::Take
        || put_back.op != Op::Put
    {
        return None;
    }
    let p = take_out.args[0];
    let (a, s, b) = (take_out.res?, slot.res?, take_back.res?);
    let ok = put_in.args == [s, a]
        && take_back.args == [s]
        && put_back.args == [p, b]
        && take_out.imm == slot.imm
        && take_out.imm == take_back.imm
        && call.args.iter().filter(|&&x| x == s).count() == 1
        && !call.args.contains(&p)
        && uses[a.index()] == 1
        && uses[b.index()] == 1
        && uses[s.index()] == 3;
    ok.then_some(p)
}
