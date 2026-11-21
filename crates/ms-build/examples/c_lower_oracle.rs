//! Prints the MIR the Rust lowering makes for each source file, so the C lowering in `compiler/`
//! can be compared with it function by function (`compiler/tests/lower-diff.sh`).
//! Temporary tooling for the C rewrite: delete it with `ms-lower`.

use ms_driver::{CheckRequest, check_graph, load_file};
use ms_lower::{Options, lower_program};

fn main() {
    let syms = ms_syntax::Names::global();
    for path in std::env::args().skip(1) {
        println!("=== {path}");
        let loaded = check_graph(
            syms,
            load_file(syms, &path, Default::default()),
            CheckRequest::default(),
        );
        let ok = loaded.success();
        let entry = loaded.entry;
        let Some(program) = loaded.program.filter(|_| ok) else {
            println!("error check");
            continue;
        };
        let options = Options { entry };
        match lower_program(syms, &program, &options) {
            Ok(module) => match ms_build::c_backend::emitted_mir(&module, false) {
                Ok(text) => print!("{text}"),
                Err(e) => println!("error {e}"),
            },
            Err(e) => println!("error {e}"),
        }
    }
}
