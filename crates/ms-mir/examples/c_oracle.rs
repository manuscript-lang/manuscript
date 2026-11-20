//! Prints, for each MIR text file, the canonical text the Rust printer gives (or the line of the
//! parse error), so the C MIR in `compiler/` can be compared with it byte for byte
//! (`make c-compiler-test`). Temporary tooling for the C rewrite: delete it with `ms-mir`.

use ms_mir::ir::{Boxing, Op};
use ms_mir::types::{AltId, Ty, TyKind};
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
        "boxing" => {
            for path in &args[1..] {
                let _ = writeln!(out, "=== {path}");
                let Some(m) = std::fs::read_to_string(path)
                    .ok()
                    .and_then(|t| parse_module(&t).ok())
                else {
                    out.push_str("error\n");
                    continue;
                };
                for a in 0..m.alts.len() {
                    let b = Boxing::default().alt(&m, AltId(a as u32));
                    let _ = writeln!(out, "alt {a} {}", b as u8);
                }
                for t in 0..m.types.len() {
                    if let TyKind::Opt(inner) = m.types.kind(Ty(t as u32)) {
                        let b = m.opt_is_boxed(*inner);
                        let _ = writeln!(out, "opt {t} {}", b as u8);
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
