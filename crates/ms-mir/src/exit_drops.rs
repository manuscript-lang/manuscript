//! The `exit_drops` pass: the program entry returns to a process that is about to exit, so the drops of
//! plain memory on its return paths (a map of types, a list of strings) only walk and free
//! memory the operating system takes back. Each such drop runs only when `msrt_exit_frees`
//! says so: the counting runtime that `make leak-check` links and `MS_FREE_AT_EXIT=1` (for
//! valgrind) keep them. Resources still close: a closer is a call, and a closure, an interface
//! value or a runtime handle is never skipped (`Module::drops_plain_memory`).

use crate::ir::*;
use crate::types::Ty;

/// Instructions that may sit between the exit drops and the return.
fn is_exit_tail(op: Op) -> bool {
    matches!(
        op,
        Op::Drop | Op::DropIf | Op::DepthLeave | Op::IConst | Op::BConst | Op::UnitConst
    )
}

/// Gates the exit drops of the entry, and of a `main` it calls once; run after the passes that
/// need to see every `drop` (`copyelim`, `simplify`) and before `lastuse`. An entry that
/// something calls again, or a `main` called from anywhere but the entry, is left alone: its
/// return is not the process exit.
pub fn run(m: &mut Module) {
    let Some(entry) = m.entry else { return };
    let mut calls = vec![Vec::new(); m.funcs.len()];
    for (fi, f) in m.funcs.iter().enumerate() {
        for i in f.blocks.iter().flat_map(|b| b.insts.iter()) {
            if let (Op::Call, Imm::Func(g)) = (i.op, i.imm) {
                calls[g.index()].push(fi);
            }
        }
    }
    let mut targets = Vec::new();
    if calls[entry.index()].is_empty() {
        targets.push(entry);
    }
    for (gi, g) in m.funcs.iter().enumerate() {
        if g.name == "main" && gi != entry.index() && calls[gi] == [entry.index()] {
            targets.push(FuncId(gi as u32));
        }
    }
    let mut gate = None;
    for fid in targets {
        gate_returns(m, fid, &mut gate);
    }
}

/// Gates the plain drops that end each returning path of `fid`. A path ends in `ret`, or in a
/// jump to a block that only builds the result and returns (what inlining `main` into the
/// entry leaves).
fn gate_returns(m: &mut Module, fid: FuncId, gate: &mut Option<ExtId>) {
    // Per block: where its run of exit drops starts, and which of them are plain.
    let mut plan: Vec<(usize, usize, Vec<bool>)> = Vec::new();
    let f = &m.funcs[fid.index()];
    for (bi, b) in f.blocks.iter().enumerate() {
        let exits = match &b.term {
            Term::Ret(_) => true,
            Term::Br(t) => {
                let c = &f.blocks[t.block.index()];
                matches!(c.term, Term::Ret(_)) && c.insts.iter().all(|i| is_exit_tail(i.op))
            }
            _ => false,
        };
        if !exits {
            continue;
        }
        let mut start = b.insts.len();
        while start > 0 && is_exit_tail(b.insts[start - 1].op) {
            start -= 1;
        }
        let plain: Vec<bool> = b.insts[start..]
            .iter()
            .map(|i| i.op == Op::Drop && m.drops_plain_memory(f.ty(i.args[0])))
            .collect();
        if plain.contains(&true) {
            plan.push((bi, start, plain));
        }
    }
    if plan.is_empty() {
        return;
    }
    let gate = *gate.get_or_insert_with(|| {
        m.add_extern(ExternDef {
            name: "msrt_exit_frees".into(),
            params: Vec::new(),
            ret: Ty::BOOL,
            noreturn: false,
            pure_: false,
            fresh: false,
            role: ExternRole::None,
            leaf: true,
            reads: false,
        })
    });
    let f = &mut m.funcs[fid.index()];
    for (bi, start, plain) in plan {
        let flag = f.new_value(Ty::BOOL);
        let loc = f.blocks[bi].insts[start].loc;
        let tail = f.blocks[bi].insts.split_off(start);
        f.blocks[bi].insts.push(Inst {
            op: Op::CallRt,
            args: Vec::new(),
            imm: Imm::Ext(gate),
            res: Some(flag),
            loc,
        });
        for (mut i, p) in tail.into_iter().zip(plain) {
            if p {
                i.op = Op::DropIf;
                i.args.insert(0, flag);
            }
            f.blocks[bi].insts.push(i);
        }
    }
}
