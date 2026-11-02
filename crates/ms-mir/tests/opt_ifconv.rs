//! Generated CFG controls for if-conversion's multi-diamond sweeps.
use ms_mir::builder::FuncBuilder;
use ms_mir::interp::Interp;
use ms_mir::ir::*;
use ms_mir::opt::ifconv;
use ms_mir::types::Ty;
use ms_mir::verify::verify_module;

fn diamonds(n: usize, condition: bool, checked: bool, reversed: bool) -> Module {
    let mut m = Module::new("diamonds");
    let mut b = FuncBuilder::new(&mut m, "main", vec![], Ty::INT);
    let cond = b
        .emit(Op::BConst, &[], Imm::Bool(condition), Some(Ty::BOOL))
        .unwrap();
    let mut value = b.iconst(0);
    for _ in 0..n {
        let then = b.new_block();
        let els = b.new_block();
        let join = b.new_block();
        let result = b.add_block_param(join, Ty::INT, Mode::Borrow);
        b.br_if(cond, then, &[], els, &[]);
        for (arm, amount) in [(then, 1), (els, 2)] {
            b.switch_to(arm);
            let amount = b.iconst(amount);
            let sum = b
                .emit(
                    if checked { Op::IAddChk } else { Op::IAdd },
                    &[value, amount],
                    Imm::None,
                    Some(Ty::INT),
                )
                .unwrap();
            b.br(join, &[sum]);
        }
        b.switch_to(join);
        value = result;
    }
    b.ret(Some(value));
    m.entry = Some(b.finish());
    if reversed {
        let f = &mut m.funcs[0];
        f.blocks[1..].reverse();
        let count = f.blocks.len();
        for block in &mut f.blocks {
            block.term.for_each_target_mut(|target| {
                if target.block.index() != 0 {
                    target.block = Block((count - target.block.index()) as u32);
                }
            });
        }
    }
    m
}

#[test]
fn independent_diamonds_preserve_results_in_both_block_orders() {
    for n in [0, 1, 2, 32, 256] {
        for condition in [false, true] {
            for reversed in [false, true] {
                let mut m = diamonds(n, condition, false, reversed);
                verify_module(&m).unwrap();
                let expected = Interp::new(&m).run_entry().unwrap();
                assert_eq!(ifconv::run(&mut m), n > 0);
                verify_module(&m).unwrap();
                assert_eq!(Interp::new(&m).run_entry().unwrap(), expected);
                assert_eq!(expected, n as i64 * if condition { 1 } else { 2 });
                assert_eq!(
                    m.funcs[0]
                        .blocks
                        .iter()
                        .flat_map(|b| &b.insts)
                        .filter(|i| i.op == Op::Select)
                        .count(),
                    n
                );
                assert!(!ifconv::run(&mut m));
            }
        }
    }
}

#[test]
fn independent_checked_diamonds_keep_their_guards() {
    for condition in [false, true] {
        for reversed in [false, true] {
            let mut m = diamonds(32, condition, true, reversed);
            verify_module(&m).unwrap();
            let before = ms_mir::print::print_module(&m);
            assert!(!ifconv::run(&mut m));
            assert_eq!(ms_mir::print::print_module(&m), before);
        }
    }
}

#[test]
fn ifconv_preserves_fixture_observations() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests");
    let mut count = 0;
    for dir in ["fixtures", "fixtures-opt"] {
        for file in std::fs::read_dir(root.join(dir)).unwrap() {
            let path = file.unwrap().path();
            if !path.extension().is_some_and(|ext| ext == "mir") {
                continue;
            }
            let mut m =
                ms_mir::parse::parse_module(&std::fs::read_to_string(&path).unwrap()).unwrap();
            verify_module(&m).unwrap();
            let observe = |m: &Module| {
                let mut interp = Interp::new(m);
                let result = interp.run_entry().map_err(|e| e.to_string());
                (result, interp.stdout().to_string(), interp.drops())
            };
            let expected = observe(&m);
            ifconv::run(&mut m);
            verify_module(&m).unwrap_or_else(|e| panic!("{}: {e:?}", path.display()));
            assert_eq!(observe(&m), expected, "{}", path.display());
            count += 1;
        }
    }
    assert!(count >= 40);
}

#[test]
fn triangles_and_shared_joins_finish_converting_for_both_outcomes() {
    for source in [
        include_str!("fixtures-opt/ifconv_triangles.mir"),
        include_str!("fixtures-opt/ifconv_shared_join.mir"),
    ] {
        for condition in [false, true] {
            let mut m = ms_mir::parse::parse_module(source).unwrap();
            for inst in m.funcs[0].blocks.iter_mut().flat_map(|b| &mut b.insts) {
                if inst.op == Op::BConst {
                    inst.imm = Imm::Bool(condition);
                }
            }
            verify_module(&m).unwrap();
            let expected = Interp::new(&m).run_entry().unwrap();
            assert!(ifconv::run(&mut m));
            verify_module(&m).unwrap();
            assert_eq!(Interp::new(&m).run_entry().unwrap(), expected);
            let blocks = &m.funcs[0].blocks;
            assert_eq!(
                blocks
                    .iter()
                    .flat_map(|b| &b.insts)
                    .filter(|i| i.op == Op::Select)
                    .count(),
                2
            );
            assert!(!blocks.iter().any(|b| matches!(b.term, Term::CondBr { .. })));
            assert!(!ifconv::run(&mut m));
        }
    }
}
