//! `exit_drops::run`: `main` skips the exit drops of plain memory and keeps the others.

use ms_mir::builder::FuncBuilder;
use ms_mir::exit_drops;
use ms_mir::ir::{Mode, Module, Op, Param};
use ms_mir::types::{Native, Ty, TyKind};

/// `main(list: List[String], handle: <opaque handle>, text: String) -> Int` returns 0 after
/// dropping all three; `callers` calls it from another function first.
fn program(recursive: bool) -> (Module, ms_mir::ir::FuncId) {
    let mut m = Module::new("exit");
    let list = m.types.intern(TyKind::List(Ty::STR));
    let handle = m
        .types
        .intern(TyKind::Obj(Native::Opaque("File".into()), vec![]));
    let own = |ty| Param {
        ty,
        mode: Mode::Move,
    };
    let mut b = FuncBuilder::new(
        &mut m,
        "main",
        vec![own(list), own(handle), own(Ty::STR)],
        Ty::INT,
    );
    let p = b.params();
    for v in &p {
        b.emit(Op::Drop, &[*v], ms_mir::ir::Imm::None, None);
    }
    let zero = b.iconst(0);
    b.ret(Some(zero));
    let main = b.finish();
    if recursive {
        let mut c = FuncBuilder::new(
            &mut m,
            "again",
            vec![own(list), own(handle), own(Ty::STR)],
            Ty::INT,
        );
        let a = c.params();
        let r = c.call(main, &a);
        c.ret(Some(r));
        c.finish();
    }
    (m, main)
}

fn count(m: &Module, f: ms_mir::ir::FuncId, op: Op) -> usize {
    m.funcs[f.index()]
        .blocks
        .iter()
        .flat_map(|b| b.insts.iter())
        .filter(|i| i.op == op)
        .count()
}

#[test]
fn plain_memory_drops_wait_on_the_runtime_gate() {
    let (mut m, main) = program(false);
    exit_drops::run(&mut m, main);
    // The list and the string are gated; the handle may own a file, so its drop stays.
    assert_eq!(count(&m, main, Op::DropIf), 2);
    assert_eq!(count(&m, main, Op::Drop), 1);
    assert_eq!(count(&m, main, Op::CallRt), 1);
}

#[test]
fn a_main_that_is_called_again_keeps_every_drop() {
    let (mut m, main) = program(true);
    exit_drops::run(&mut m, main);
    assert_eq!(count(&m, main, Op::DropIf), 0);
    assert_eq!(count(&m, main, Op::Drop), 3);
}
