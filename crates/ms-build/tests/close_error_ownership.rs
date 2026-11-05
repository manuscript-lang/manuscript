//! Scope-close outcomes participate in the same Result ownership contract as source returns.
use ms_driver::{CheckRequest, LoadOptions, check_graph, load_file};
use ms_mir::ir::Op;
use ms_mir::types::{Std, TyKind};

#[test]
fn close_errors_preserve_owned_identity_and_disjoint_borrowing() {
    let syms = ms_syntax::Names::global();
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../tests/e2e/testdata/accept/close-error-precedence.ms"
    );
    let loaded = check_graph(
        syms,
        load_file(syms, path, LoadOptions { tests: true }),
        CheckRequest::default(),
    );
    assert!(loaded.success(), "{:?}", loaded.diagnostics);
    let (module, _) = ms_lower::lower_tests(
        syms,
        &loaded.program.expect("program"),
        &ms_lower::Options {
            entry: loaded.entry,
        },
    )
    .expect("lower precedence and borrowing fixture");
    ms_mir::verify::verify_module(&module).expect("ownership verified without exceptions");

    for (name, borrowed) in [
        ("borrowed_ok", 1 << Std::OK),
        ("forward_ok", 1 << Std::OK),
        ("consumed_parameter", 1 << Std::OK),
        ("mixed_error", 1 << Std::ERROR),
        ("forward_error", 0),
    ] {
        let f = module.funcs.iter().find(|f| f.name == name).expect(name);
        let TyKind::Alt(a) = module.types.kind(f.ret) else {
            panic!("{name} must return a Result");
        };
        assert_eq!(module.alts[a.index()].std, Std::Result);
        assert_eq!(module.alts[a.index()].borrowed, borrowed, "{name}");
        assert!(!f.ret_borrowed, "{name} owns its nonborrowed cases");
    }
    for name in ["work", "propagated"] {
        let f = module.funcs.iter().find(|f| f.name == name).expect(name);
        for i in f.blocks.iter().flat_map(|b| &b.insts) {
            if i.op == Op::Clone
                && let TyKind::Rec(r) = module.types.kind(f.ty(i.args[0]))
            {
                assert_ne!(
                    module.records[r.index()].name,
                    "Error",
                    "{name} must keep the original owned Error"
                );
            }
        }
    }
    let borrowed = module
        .funcs
        .iter()
        .find(|f| f.name == "borrowed_custom")
        .expect("borrowed_custom");
    assert!(
        borrowed.ret_borrowed,
        "incompatible close errors fault, so this custom error stays borrowed"
    );
}
