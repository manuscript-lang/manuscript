//! Reused-session check cost, excluding source parsing and initial library loading.
use std::hint::black_box;
use std::sync::Arc;
use std::time::Instant;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let source = std::fs::read_to_string(&args[1]).expect("source");
    let iterations: usize = args[2].parse().expect("iterations");
    assert!(iterations > 0);
    let names = ms_syntax::Names::global();
    let session = ms_check::Session::new();
    session.ensure_standard();
    let file: Arc<str> = Arc::from("bench.ms");
    let parsed = ms_syntax::parser::parse(&file, &source).expect("valid source");
    let check = || {
        let module = ms_check::load_module(names, &parsed);
        let program = ms_check::check_in(
            names,
            &session,
            vec![module],
            ms_check::ImportMap::default(),
            ms_check::CheckOptions::default(),
        );
        assert!(program.diagnostics.is_empty(), "{:?}", program.diagnostics);
        black_box(program);
    };
    check();
    let start = Instant::now();
    for _ in 0..iterations {
        check();
    }
    let elapsed = start.elapsed().as_nanos();
    println!("{{\"iterations\":{iterations},\"diagnostics\":[],\"elapsed_ns\":{elapsed}}}");
}
