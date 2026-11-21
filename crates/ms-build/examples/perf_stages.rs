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
    let syms = ms_syntax::Names::global();
    let args: Vec<String> = std::env::args().collect();
    assert_eq!(args.len(), 4, "perf_stages source output runtime-archive");
    let graph = stage("load_parse", || {
        ms_driver::load_file(syms, &args[1], Default::default())
    });
    let checked = stage("check", || {
        ms_driver::check_graph(
            syms,
            graph,
            ms_driver::CheckRequest {
                entry: true,
                ..ms_driver::CheckRequest::default()
            },
        )
    });
    assert!(checked.success(), "{:?}", checked.diagnostics);
    let module = stage("lower", || {
        Native
            .lower(checked.program.as_ref().unwrap(), &checked.entry)
            .unwrap()
    });
    stage("drop_checked", || drop(checked));
    stage("verify", || ms_mir::verify::verify_module(&module).unwrap());
    stage("llvm_available", || {
        assert!(
            ms_build::llvm_available(&ms_build::BuildOptions::default()),
            "LLVM is required; fallback is not a measurement"
        )
    });
    // The C back end optimizes, finishes the MIR and writes the object in one call, so those
    // stages are measured together.
    let build = ms_build::BuildOptions::default();
    let llvm_object = stage("codegen", || {
        ms_build::c_backend::compile(&module, true, true, &build).unwrap()
    });
    let output = Path::new(&args[2]);
    let object = output.with_extension("llvm.o");
    stage("write_objects", || {
        std::fs::write(&object, llvm_object).unwrap()
    });
    stage("link", || {
        ms_build::link::link_with(
            &object,
            &[Path::new(&args[3])],
            output,
            false,
            &ms_build::BuildOptions::default(),
        )
        .unwrap()
    });
    std::fs::remove_file(object).unwrap();
    stage("drop_mir", || drop(module));
}
