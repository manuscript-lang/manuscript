//! Prints, for each MIR text file, the canonical text the Rust printer gives (or the line of the
//! parse error), so the C MIR in `compiler/` can be compared with it byte for byte
//! (`make c-compiler-test`). Temporary tooling for the C rewrite: delete it with `ms-mir`.

use ms_mir::ir::Op;
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use std::fmt::Write;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut out = String::new();
    match args[0].as_str() {
        "ops" => {
            for op in Op::ALL {
                let i = op.info();
                let e = i.effects;
                let fx = e.reads as u8
                    | (e.writes as u8) << 1
                    | (e.faults as u8) << 2
                    | (e.ownership as u8) << 3
                    | (e.alloc as u8) << 4
                    | (e.io as u8) << 5;
                let imm = i.imm as u8;
                let _ = writeln!(
                    out,
                    "{} imm={imm} res={} fx={fx}",
                    i.name, i.has_result as u8
                );
            }
        }
        "valid" => {
            // The files whose module parses and verifies: the ones a pass may be run on.
            for path in &args[1..] {
                let Ok(text) = std::fs::read_to_string(path) else {
                    continue;
                };
                if parse_module(&text).is_ok_and(|m| ms_mir::verify::verify_module(&m).is_ok()) {
                    let _ = writeln!(out, "{path}");
                }
            }
        }
        "pass" => {
            let pass = args[1].as_str();
            for path in &args[2..] {
                let bytes = std::fs::read(path).expect("read");
                let _ = writeln!(out, "=== {path}");
                let Ok(text) = std::str::from_utf8(&bytes) else {
                    out.push_str("error invalid-utf8\n");
                    continue;
                };
                let mut m = match parse_module(text) {
                    Ok(m) => m,
                    Err(e) => {
                        let _ = writeln!(out, "error line {}", e.line);
                        continue;
                    }
                };
                let changed = run_pass(pass, &mut m);
                let _ = writeln!(out, "changed {}", changed as u8);
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
        _ => {
            for path in &args[1..] {
                let bytes = std::fs::read(path).expect("read");
                let _ = writeln!(out, "=== {path}");
                let Ok(text) = std::str::from_utf8(&bytes) else {
                    out.push_str("error invalid-utf8\n");
                    continue;
                };
                match parse_module(text) {
                    Ok(m) => out.push_str(&print_module(&m)),
                    Err(e) => {
                        let _ = writeln!(out, "error line {}", e.line);
                    }
                }
            }
        }
    }
    print!("{out}");
}

/// Runs the pass `name` on `m` and returns whether it reports a change. The C port in
/// `compiler/src/mir_*.c` has the same names in `compiler/tools/ms_mir_dump.c`.
fn run_pass(name: &str, m: &mut ms_mir::ir::Module) -> bool {
    match name {
        "exit_drops" => {
            ms_mir::exit_drops::run(m);
            true
        }
        "expand" => ms_mir::expand::run(m, true),
        "expand-nochecks" => ms_mir::expand::run(m, false),
        other => panic!("unknown pass {other}"),
    }
}
