//! Lowers small programs and verifies the MIR.

use ms_lower::{Options, load, lower_program};
use std::path::PathBuf;

fn lower(name: &str, source: &str) -> String {
    let dir = std::env::temp_dir().join(format!("ms-lower-{}-{name}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("dir");
    let path: PathBuf = dir.join("main.ms");
    std::fs::write(&path, source).expect("write");
    let loaded = load::load(&path);
    let _ = std::fs::remove_dir_all(&dir);
    assert!(loaded.diagnostics.is_empty(), "{:?}", loaded.diagnostics);
    let program = loaded.program.expect("program");
    let module = lower_program(
        &program,
        &Options {
            entry: loaded.entry,
        },
    )
    .expect("lower");
    ms_mir::verify::verify_module(&module).expect("verified MIR");
    ms_mir::print::print_module(&module)
}

#[test]
fn strings_and_loops() {
    let mir = lower(
        "strings",
        "import stdout from \"@std/io.ms\"\n\nexport fn main() Int:\n    var total = 0\n    for x in [1, 2, 3]:\n        total += x\n    let r = stdout().write(\"total {total}\\n\")\n    return 0\n",
    );
    assert!(mir.contains("msrt_string_concat"));
    assert!(mir.contains("iadd.chk"));
}

#[test]
fn caller_evaluated_defaults() {
    let mir = lower(
        "defaults",
        "fn pad(x: Int, by: Int = 2) Int:\n    return x + by\n\nexport fn main() Int:\n    return pad(1)\n",
    );
    assert!(mir.contains("fn @pad"));
}
