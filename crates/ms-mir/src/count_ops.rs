//! The `count_ops` pass: a build for `ms bench --ops` adds, at the start of every block, a call that
//! adds the block's instruction count to a process-wide total. The total counts MIR operations the
//! program executes, so it is the same on every platform and backend, does not move with machine
//! load, and covers the code a Manuscript project wrote (not the runtime beneath it). Run after
//! the optimizer, so it counts the code that is compiled, and before `unwind`; the call is a leaf,
//! so it adds no cancellation point.

use crate::ir::*;
use crate::types::Ty;

/// Adds the counting call to every block of every function.
pub fn run(m: &mut Module) {
    let add = m.add_extern(ExternDef {
        name: "msrt_ops_add".into(),
        params: vec![Param {
            ty: Ty::INT,
            mode: Mode::Borrow,
        }],
        ret: Ty::VOID,
        noreturn: false,
        pure_: false,
        fresh: false,
        leaf: true,
        reads: false,
        role: ExternRole::None,
    });
    for f in &mut m.funcs {
        for b in 0..f.blocks.len() {
            // The instructions plus the terminator.
            let n = f.blocks[b].insts.len() as i64 + 1;
            let loc = f.blocks[b]
                .insts
                .first()
                .map_or(f.blocks[b].term_loc, |i| i.loc);
            let count = f.new_value(Ty::INT);
            let done = f.new_value(Ty::VOID);
            let head = [
                Inst {
                    op: Op::IConst,
                    args: Vec::new(),
                    imm: Imm::Int(n),
                    res: Some(count),
                    loc,
                },
                Inst {
                    op: Op::CallRt,
                    args: vec![count],
                    imm: Imm::Ext(add),
                    res: Some(done),
                    loc,
                },
            ];
            f.blocks[b].insts.splice(0..0, head);
        }
    }
}
