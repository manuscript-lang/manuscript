use ms_check::api::ast::*;
use ms_check::*;
fn main() {
    let syms = ms_check::api::Names::global();
    let session = Session::new();
    session.ensure_standard();
    for path in std::env::args().skip(1) {
        let source = std::fs::read_to_string(&path).unwrap();
        let file: std::sync::Arc<str> = "main.ms".into();
        let module = ms_syntax::parser::parse(&file, &source).unwrap();
        let loaded = ms_check::load_module(syms, &module);
        let program = ms_check::check_in(syms, &session, vec![loaded.clone()], ms_check::ImportMap::default(), ms_check::CheckOptions::default());
        for d in &program.diagnostics {
            println!("{}:{}: {:?} {}", d.pos.line, d.pos.column, d.phase, d.message);
        }
    }
}
