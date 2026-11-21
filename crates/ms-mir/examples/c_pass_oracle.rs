//! Runs a MIR pass on each verified MIR text file and prints the module the Rust pass leaves, so the
//! C passes in `compiler/src/mir/*.c` can be compared byte for byte (`compiler/tests/mir-pass-diff.sh`).
//! Temporary tooling for the C rewrite: delete it with `ms-mir`.
//!
//! `valid FILE...` prints the files whose module parses and verifies. `pass NAME FILE...` prints, per
//! file, `changed N`, the module text, and the cold blocks of each function.

use ms_mir::parse::parse_module;
use ms_mir::print::print_module_raw as print_module;
use std::fmt::Write;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut out = String::new();
    match args[0].as_str() {
        "valid" => {
            for path in &args[1..] {
                let Ok(text) = std::fs::read_to_string(path) else {
                    continue;
                };
                if parse_module(&text).is_ok_and(|m| ms_mir::verify::verify_module(&m).is_ok()) {
                    let _ = writeln!(out, "{path}");
                }
            }
        }
        _ => {
            let pass = args[1].as_str();
            for path in &args[2..] {
                let text = std::fs::read_to_string(path).expect("read");
                let _ = writeln!(out, "=== {path}");
                let Ok(mut m) = parse_module(&text) else {
                    out.push_str("error\n");
                    continue;
                };
                let changed = match run_pass(pass, &mut m) {
                    Ok(changed) => changed,
                    Err(e) => {
                        let _ = writeln!(out, "fail {e}");
                        continue;
                    }
                };
                let _ = writeln!(out, "changed {}", changed as u8);
                if pass == "copies" {
                    for site in ms_mir::copies::object_copies(&m) {
                        let _ = writeln!(out, "{site}");
                    }
                    continue;
                }
                if pass == "frames" {
                    for f in &m.funcs {
                        let sorted = |s: std::collections::HashSet<usize>| {
                            let mut v: Vec<usize> = s.into_iter().collect();
                            v.sort_unstable();
                            v.iter().map(|i| format!(" {i}")).collect::<String>()
                        };
                        let iface = sorted(ms_mir::frames::framed_iface_borrows(&m, f));
                        let closure = sorted(ms_mir::frames::framed_closure_objects(&m, f));
                        let _ = writeln!(out, "{} iface:{iface} closure:{closure}", f.name);
                    }
                    continue;
                }
                out.push_str(&print_module(&m));
                for f in &m.funcs {
                    let mut cold: Vec<u32> = f.cold.iter().map(|b| b.0).collect();
                    cold.sort_unstable();
                    if !cold.is_empty() {
                        let _ = writeln!(out, "cold {}: {cold:?}", f.name);
                    }
                }
            }
        }
    }
    print!("{out}");
}

/// Runs the pass `name` on `m` and returns whether it reports a change; `compiler/tools/ms_mir_pass.c`
/// has the same names.
fn run_pass(name: &str, m: &mut ms_mir::ir::Module) -> Result<bool, String> {
    if name == "elaborate" {
        return ms_mir::elaborate::run(m).map(|()| true);
    }
    if name == "elaborate-cancel" {
        return ms_mir::elaborate::run_with(m, true).map(|()| true);
    }
    Ok(match name {
        "expand" => ms_mir::expand::run(m, true),
        "expand-nochecks" => ms_mir::expand::run(m, false),
        "expand_owned" => ms_mir::expand_owned::run(m),
        "unwind" => ms_mir::unwind::run(m),
        "glue" => ms_mir::glue::run(m),
        "frames" | "copies" => true,
        "glue_expand" => {
            ms_mir::glue::run_and_expand(m);
            true
        }
        other => panic!("unknown pass {other}"),
    })
}
