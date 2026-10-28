import pathlib, re, json, sys
repo, out = (pathlib.Path(x).resolve() for x in sys.argv[1:3])
(out / 'src').mkdir(parents=True, exist_ok=True)
(out / 'Cargo.toml').write_text('''[package]
name = "type-bench"
version = "0.0.0"
edition = "2024"
[dependencies]
ms-syntax = { path = PATH }
[profile.release]
debug = 1
panic = "abort"
'''.replace('PATH', json.dumps(str(repo / 'crates/ms-syntax'))))
build = (repo / 'crates/ms-check/build.rs').read_text()
(out / 'build.rs').write_text(build.replace('.join("../../stdlib")', '.join(' + json.dumps(str(repo / 'stdlib')) + ')'))
lib = (repo / 'crates/ms-check/src/lib.rs').read_text().split('/// Checks modules given in dependency order.')[0]
def module_path(m):
    p = repo / 'crates/ms-check/src' / (m[2] + '.rs')
    if not p.exists(): p = p.with_suffix('') / 'mod.rs'
    return '#[path = ' + json.dumps(str(p)) + ']\n' + m[0]
lib = re.sub(r'^(pub )?mod (\w+);', module_path, lib, flags=re.M)
lib += '''
pub fn check_types(modules: Vec<ModRef>) -> Program {
    stdlib::ensure_standard();
    checker::Checker::new(&CheckOptions::default()).check_modules(modules, None)
}
pub fn validate(p: &Program) {
    assert!(p.diagnostics.is_empty(), "{:?}", p.diagnostics);
    assert!(unused::check(p).is_empty(), "unused local");
    let names = p.symbols[&types::n("bench.ms")].borrow();
    let main = names[&types::n("main")].ty.borrow();
    assert_eq!(main.as_ref().unwrap().result_ty().id.as_str(), "Int");
}
'''
(out / 'src/lib.rs').write_text(lib)
(out / 'src/main.rs').write_text('''use std::{sync::Arc, time::Instant};
fn main() {
    std::thread::Builder::new().stack_size(64 << 20).spawn(run).unwrap().join().unwrap();
}
fn run() {
    let args: Vec<_> = std::env::args().collect();
    let source = std::fs::read_to_string(&args[1]).unwrap();
    let count: usize = args.get(2).map(|x| x.parse().unwrap()).unwrap_or(6);
    let file: Arc<str> = Arc::from("bench.ms");
    let start = Instant::now();
    type_bench::stdlib::ensure_standard();
    eprintln!("stdlib_init_ms={:.6}", start.elapsed().as_secs_f64() * 1000.);
    println!("iteration,bytes,parse_ms,load_ms,check_ms");
    for i in 0..count {
        let start = Instant::now();
        let ast = ms_syntax::parser::parse(&file, &source).expect("valid syntax");
        let parse = start.elapsed().as_secs_f64() * 1000.;
        let start = Instant::now();
        let module = type_bench::load_module(&ast);
        let load = start.elapsed().as_secs_f64() * 1000.;
        let start = Instant::now();
        let program = type_bench::check_types(vec![module]);
        let check = start.elapsed().as_secs_f64() * 1000.;
        type_bench::validate(&program); // outside timed region
        println!("{i},{},{parse:.6},{load:.6},{check:.6}", source.len());
    }
}
''')
