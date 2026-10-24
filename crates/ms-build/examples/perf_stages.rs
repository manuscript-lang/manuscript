//! Diagnostic stage timer; see bench/perf/representative/README.md.
use std::path::Path;
use std::time::Instant;

use ms_build::{Lower, Native};

fn stage<T>(name: &str, f: impl FnOnce() -> T) -> T {
    let started = Instant::now();
    let value = f();
    eprintln!(
        "{{\"stage\":\"{name}\",\"seconds\":{:.9}}}",
        started.elapsed().as_secs_f64()
    );
    value
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    assert_eq!(args.len(), 4, "perf_stages source output runtime-archive");
    let graph = stage("load_parse", || {
        ms_driver::load_file(&args[1], Default::default())
    });
    let checked = stage("check", || {
        ms_driver::check_graph(graph, ms_driver::CheckRequest { entry: true })
    });
    assert!(checked.success(), "{:?}", checked.diagnostics);
    let mut module = stage("lower", || {
        Native
            .lower(checked.program.as_ref().unwrap(), &checked.entry)
            .unwrap()
    });
    stage("drop_checked", || drop(checked));
    stage("verify", || ms_mir::verify::verify_module(&module).unwrap());
    stage("llvm_available", || {
        assert!(
            ms_clif::llvm_available(),
            "LLVM is required; fallback is not a measurement"
        )
    });
    stage("mir_opt", || {
        if std::env::var_os("MS_PERF_MIR_PASSES").is_some() {
            mir_passes(&mut module);
        } else {
            ms_mir::opt::optimize(&mut module, ms_mir::opt::Level::Speed, false);
        }
    });
    let options = ms_clif::Options {
        llvm: Some("3"),
        ..Default::default()
    };
    let parts = stage("codegen", || {
        ms_clif::compile_parts(&module, &options).unwrap()
    });
    let llvm = parts.llvm.expect("LLVM must actually emit an object");
    let output = Path::new(&args[2]);
    let object = output.with_extension("clif.o");
    let llvm_object = output.with_extension("llvm.o");
    stage("write_objects", || {
        std::fs::write(&object, parts.object).unwrap();
        std::fs::write(&llvm_object, llvm).unwrap();
    });
    stage("link", || {
        ms_clif::link::link_with(&object, &[&llvm_object, Path::new(&args[3])], output, false)
            .unwrap()
    });
    std::fs::remove_file(object).unwrap();
    std::fs::remove_file(llvm_object).unwrap();
    stage("drop_mir", || drop(module));
}

// Diagnostic replay of the fixed pipeline, kept separate from the measured CLI.
// Mirrors ms-mir/src/opt/mod.rs at the revision recorded in the report.
fn mir_passes(m: &mut ms_mir::ir::Module) {
    use ms_mir::opt::*;
    stage("mir_simplify_initial", || simplify::run(m));
    stage("mir_copyelim_initial", || copyelim::run(m));
    stage("mir_inline", || inline::run(m));
    stage("mir_strfuse", || strfuse::run(m));
    stage("mir_slotfuse", || slotfuse::run(m));
    for round in 0..3 {
        let mut changed = stage(&format!("mir_optparam_{round}"), || optparam::run(m));
        changed |= stage(&format!("mir_simplify_{round}"), || simplify::run(m));
        changed |= stage(&format!("mir_copyelim_{round}"), || copyelim::run(m));
        changed |= stage(&format!("mir_range_{round}"), || range::run(m));
        changed |= stage(&format!("mir_ifconv_{round}"), || ifconv::run(m));
        if !changed && round > 0 {
            break;
        }
    }
    stage("mir_reserve", || reserve::run(m));
    stage("mir_simplify_final", || simplify::run(m));
}
