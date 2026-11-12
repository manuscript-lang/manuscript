//! The `exit_drops` pass: `main` returns to a process that is about to exit, so the drops of
//! plain memory on its return paths (a map of records, a list of strings) only walk and free
//! memory the operating system takes back. Each such drop runs only when `msrt_exit_frees`
//! says so: the counting runtime that `make leak-check` links and `MS_FREE_AT_EXIT=1` (for
//! valgrind) keep them. Resources still close: a closer is a call, and a closure, an interface
//! value or a runtime handle is never skipped (`Module::drops_plain_memory`).

use crate::ir::*;
use crate::types::Ty;

/// Gates the exit drops of `main`, unless something calls `main` again: then its return is not
/// the process exit.
pub fn run(m: &mut Module, main: FuncId) {
    let called = m.funcs.iter().any(|f| {
        f.blocks.iter().any(|b| {
            b.insts
                .iter()
                .any(|i| i.op == Op::Call && i.imm == Imm::Func(main))
        })
    });
    if called {
        return;
    }
    // Per returning block: where its run of exit drops starts, and which of them are plain.
    let mut plan: Vec<(usize, usize, Vec<bool>)> = Vec::new();
    let f = &m.funcs[main.index()];
    for (bi, b) in f.blocks.iter().enumerate() {
        if !matches!(b.term, Term::Ret(_)) {
            continue;
        }
        let mut start = b.insts.len();
        // The drops, the constants a return value is made of, and the depth accounting.
        while start > 0
            && matches!(
                b.insts[start - 1].op,
                Op::Drop | Op::DropIf | Op::DepthLeave | Op::IConst | Op::BConst | Op::UnitConst
            )
        {
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
    let gate = m.add_extern(ExternDef {
        name: "msrt_exit_frees".into(),
        params: Vec::new(),
        ret: Ty::BOOL,
        noreturn: false,
        pure_: false,
        fresh: false,
        role: ExternRole::None,
        leaf: true,
        reads: false,
    });
    let f = &mut m.funcs[main.index()];
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
