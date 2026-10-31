//! A Windows fault assertion resumes its caller, so unwinding must retain the caller's values.
use ms_driver::{CheckRequest, LoadOptions, check_graph, load_file};
use ms_mir::ir::{Imm, InlineHint, Mode, Op};
use ms_mir::opt::{Level, optimize};
use ms_rt as _;

#[test]
fn fault_assertions_keep_caller_values_outside_the_trap() {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../tests/e2e/testdata/accept/implicit-close-shielded.ms"
    );
    for level in [Level::None, Level::Speed] {
        let loaded = check_graph(
            load_file(path, LoadOptions { tests: true }),
            CheckRequest::default(),
        );
        assert!(loaded.success(), "{:?}", loaded.diagnostics);
        let (mut module, _) = ms_lower::lower_tests(
            &loaded.program.expect("program"),
            &ms_lower::Options {
                entry: loaded.entry,
            },
        )
        .expect("lower original cleanup fixture");
        optimize(&mut module, level, true);
        assert!(ms_mir::unwind::run(&mut module), "exercise unwind lowering");
        ms_mir::verify::verify_module(&module).expect("verified unwind MIR");

        let traps: Vec<_> = module
            .funcs
            .iter()
            .filter(|f| {
                f.blocks.iter().flat_map(|b| &b.insts).any(|i| {
                    matches!((i.op, i.imm), (Op::CallRt, Imm::Ext(e))
                        if module.externs[e.index()].name == "msrt_trap_begin")
                })
            })
            .collect();
        assert!(!traps.is_empty(), "retain the fault assertion at {level:?}");
        for f in traps {
            assert_eq!(f.inline, InlineHint::Never, "retain the trap boundary");
            assert!(f.params.iter().all(|p| p.mode == Mode::Borrow));
            assert!(
                f.blocks
                    .iter()
                    .flat_map(|b| &b.insts)
                    .any(|i| i.op == Op::CallInd)
            );
            assert!(
                !f.blocks
                    .iter()
                    .flat_map(|b| &b.insts)
                    .any(|i| i.op == Op::CleanupPush),
                "trap frame must not register drops for values its caller still owns: {} at {level:?}",
                f.name
            );
        }
    }
}
