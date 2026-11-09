//! `FuncBuilder::outline` and `list.const`.

use ms_mir::builder::FuncBuilder;
use ms_mir::interp::Interp;
use ms_mir::ir::{Module, Op};
use ms_mir::types::Ty;
use ms_mir::verify::verify_module;

/// `main` computes `x + 1 .. x + 3` into a list, optionally in an outlined helper, and returns
/// the sum of the elements read back plus the length.
fn program(outline: bool) -> Module {
    let mut m = Module::new("outline");
    let mut b = FuncBuilder::new(&mut m, "main", vec![], Ty::INT);
    let x = b.iconst(10);
    let mark = b.mark();
    let items: Vec<_> = (1..=3)
        .map(|k| {
            let k = b.iconst(k);
            b.binop(Op::IAdd, x, k)
        })
        .collect();
    let mut list = b.list_lit(Ty::INT, &items);
    if outline {
        list = b.outline(mark, list, "list.literal.0").expect("outlined");
    }
    let (i0, i2) = (b.iconst(0), b.iconst(2));
    let (a, c) = (b.list_get(list, i0), b.list_get(list, i2));
    let n = b.list_len(list);
    let s = b.binop(Op::IAdd, a, c);
    let total = b.binop(Op::IAdd, s, n);
    b.emit(Op::Drop, &[list], ms_mir::ir::Imm::None, None);
    b.ret(Some(total));
    let id = b.finish();
    m.entry = Some(id);
    m
}

fn run(m: &Module) -> i64 {
    verify_module(m).unwrap_or_else(|e| panic!("{e:?}"));
    Interp::new(m).run_entry().unwrap_or_else(|f| panic!("{f}"))
}

#[test]
fn an_outlined_run_computes_what_it_computed_in_place() {
    let inline = program(false);
    let outlined = program(true);
    assert_eq!(outlined.funcs.len(), inline.funcs.len() + 1);
    assert_eq!(run(&inline), 11 + 13 + 3);
    assert_eq!(run(&outlined), run(&inline));
}

#[test]
fn a_run_that_reads_a_droppable_value_stays_in_place() {
    let mut m = Module::new("outline");
    let mut b = FuncBuilder::new(&mut m, "main", vec![], Ty::INT);
    let s = b.str_lit("abc");
    let mark = b.mark();
    let n = b.str_len(s);
    let list = b.list_lit(Ty::INT, &[n]);
    assert!(b.outline(mark, list, "list.literal.0").is_none());
}

#[test]
fn list_const_yields_the_registered_elements() {
    let mut m = Module::new("const");
    let mut b = FuncBuilder::new(&mut m, "main", vec![], Ty::INT);
    let list = b.list_const(Ty::INT, vec![5, -2, 40]);
    let i1 = b.iconst(1);
    let got = b.list_get(list, i1);
    let n = b.list_len(list);
    let total = b.binop(Op::IAdd, got, n);
    b.emit(Op::Drop, &[list], ms_mir::ir::Imm::None, None);
    b.ret(Some(total));
    let id = b.finish();
    m.entry = Some(id);
    assert_eq!(run(&m), -2 + 3);
}

/// `main` stores `x + 1` in a slot made inside the run and reads it back.
fn slot_program(outline: bool) -> Module {
    use ms_mir::ir::Imm;
    let mut m = Module::new("outline");
    let mut b = FuncBuilder::new(&mut m, "main", vec![], Ty::INT);
    let x = b.iconst(41);
    let mark = b.mark();
    let one = b.iconst(1);
    let sum = b.binop(Op::IAdd, x, one);
    let slot = b
        .emit(Op::Slot, &[], Imm::Ty(Ty::INT), Some(Ty::PTR))
        .unwrap();
    b.emit(Op::Store, &[slot, sum], Imm::None, None);
    let mut got = b
        .emit(Op::Load, &[slot], Imm::Ty(Ty::INT), Some(Ty::INT))
        .unwrap();
    if outline {
        got = b.outline(mark, got, "slot.run").expect("outlined");
    }
    b.ret(Some(got));
    let id = b.finish();
    m.entry = Some(id);
    m
}

#[test]
fn a_slot_made_and_used_inside_the_run_moves_with_it() {
    let inline = slot_program(false);
    let outlined = slot_program(true);
    assert_eq!(outlined.funcs.len(), inline.funcs.len() + 1);
    assert_eq!(run(&inline), 42);
    assert_eq!(run(&outlined), 42);
}
