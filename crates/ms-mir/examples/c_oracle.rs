//! Prints, for each MIR text file, the canonical text the Rust printer gives (or the line of the
//! parse error), so the C MIR in `compiler/` can be compared with it byte for byte
//! (`make c-compiler-test`). Temporary tooling for the C rewrite: delete it with `ms-mir`.

use ms_mir::ir::{Mode, Module, Op};
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
        "analysis" => each_module(&args[1..], &mut out, |m, out| {
            for f in &m.funcs {
                analysis(m, f, out);
            }
        }),
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

fn each_module(paths: &[String], out: &mut String, mut run: impl FnMut(&Module, &mut String)) {
    for path in paths {
        let bytes = std::fs::read(path).expect("read");
        let _ = writeln!(out, "=== {path}");
        match std::str::from_utf8(&bytes).map(parse_module) {
            Ok(Ok(m)) => run(&m, out),
            Ok(Err(e)) => {
                let _ = writeln!(out, "error line {}", e.line);
            }
            Err(_) => out.push_str("error invalid-utf8\n"),
        }
    }
}

fn mode_char(m: Mode) -> char {
    match m {
        Mode::Borrow => 'B',
        Mode::Move => 'M',
        Mode::Var => 'V',
    }
}

/// The control-flow and ownership facts of `f` that the C analysis must reproduce.
fn analysis(m: &Module, f: &ms_mir::ir::Func, out: &mut String) {
    let ids = |v: &[ms_mir::ir::Block]| {
        v.iter()
            .map(|b| b.index().to_string())
            .collect::<Vec<_>>()
            .join(" ")
    };
    let _ = writeln!(out, "func {}", f.name);
    let rpo = f.rpo();
    let preds = f.predecessors();
    let _ = writeln!(out, "rpo {}", ids(&rpo));
    for (b, p) in preds.iter().enumerate() {
        let _ = writeln!(out, "preds {b}: {}", ids(p));
    }
    let idom = ms_mir::verify::dominators(f, &rpo, &preds);
    let text: Vec<String> = idom
        .iter()
        .map(|&d| if d == usize::MAX { "-".into() } else { d.to_string() })
        .collect();
    let _ = writeln!(out, "idom {}", text.join(" "));
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            let res = m.result_mode(f, inst).map_or('-', mode_char);
            let modes: String = ms_mir::verify::arg_modes(m, f, inst)
                .into_iter()
                .map(mode_char)
                .collect();
            let views = u8::from(m.result_views(f, inst));
            let owned = ms_mir::verify::indirect_owned(m, f, inst);
            let _ = writeln!(out, "{bi}.{ii} res={res} views={views} owned={owned:x} args={modes}");
        }
    }
}
