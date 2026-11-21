//! Prints, for each MIR text file, the canonical text the Rust printer gives (or the line of the
//! parse error), so the C MIR in `compiler/` can be compared with it byte for byte
//! (`make c-compiler-test`). Temporary tooling for the C rewrite: delete it with `ms-mir`.

use ms_mir::interp::Interp;
use ms_mir::ir::{Boxing, Mode, Module, Op};
use ms_mir::layout::{AltRepr, Layouts, Leaf, mem_layout};
use ms_mir::parse::parse_module;
use ms_mir::print::print_module;
use ms_mir::types::{AltId, Ty, TyKind};
use std::fmt::Write;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut out = String::new();
    std::panic::set_hook(Box::new(|_| {}));
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
        "verify" => each_module(&args[1..], &mut out, |m, out| {
            // A mutant can reach an index the verifier does not check: say so, and let the
            // comparison skip the file.
            match std::panic::catch_unwind(|| ms_mir::verify::verify_module(m)) {
                Ok(Ok(())) => out.push_str("ok\n"),
                Ok(Err(errs)) => {
                    for e in errs {
                        let _ = writeln!(out, "{e}");
                    }
                }
                Err(_) => out.push_str("oracle-panic\n"),
            }
        }),
        "analysis" => each_module(&args[1..], &mut out, |m, out| {
            for f in &m.funcs {
                analysis(m, f, out);
            }
        }),
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
        "run" => {
            for path in &args[1..] {
                let _ = writeln!(out, "=== {path}");
                let Some(m) = std::fs::read_to_string(path)
                    .ok()
                    .and_then(|t| parse_module(&t).ok())
                else {
                    out.push_str("error\n");
                    continue;
                };
                run_module(&m, &mut out);
            }
        }
        "layout" => {
            for path in &args[1..] {
                let _ = writeln!(out, "=== {path}");
                let Some(m) = std::fs::read_to_string(path)
                    .ok()
                    .and_then(|t| parse_module(&t).ok())
                else {
                    out.push_str("error\n");
                    continue;
                };
                dump_layout(&m, &mut out);
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

fn leaf_list(leaves: &[Leaf]) -> String {
    let names: Vec<String> = leaves
        .iter()
        .map(|l| format!("{l:?}").to_lowercase())
        .collect();
    names.join(",")
}

fn flags(v: &[bool]) -> String {
    v.iter().map(|b| if *b { '1' } else { '0' }).collect()
}

fn nums<T: std::fmt::Display>(v: &[T]) -> String {
    let s: Vec<String> = v.iter().map(|x| x.to_string()).collect();
    s.join(",")
}

/// One block of lines per type, alternative, indirect record and function; the C dump prints the same.
fn dump_layout(m: &ms_mir::ir::Module, out: &mut String) {
    let lay = Layouts::new(m);
    for t in 0..m.types.len() {
        let ty = Ty(t as u32);
        let shape = lay.shape(ty);
        let mem = mem_layout(&shape.leaves);
        let _ = writeln!(
            out,
            "ty {t} leaves={} size={} align={} off={} ptr={} bool={} str={}",
            leaf_list(&shape.leaves),
            mem.size,
            mem.align,
            nums(&mem.offsets),
            flags(&lay.pointer_leaves(ty)),
            flags(&lay.bool_leaves(ty)),
            lay.is_str_like(ty) as u8
        );
        match m.types.kind(ty) {
            TyKind::Opt(inner) => {
                let _ = writeln!(out, "  nullable={}", lay.opt_is_nullable(*inner) as u8);
            }
            TyKind::Alt(a) => {
                let _ = writeln!(out, "  boxed={}", lay.is_boxed(*a) as u8);
                match &shape.alt {
                    Some(AltRepr::Inline { slots }) => {
                        for (c, s) in slots.iter().enumerate() {
                            let _ = writeln!(out, "  inline case {c} slots={}", nums(s));
                        }
                    }
                    Some(AltRepr::Boxed { slots, block }) => {
                        for (c, s) in slots.iter().enumerate() {
                            let _ = writeln!(out, "  boxed case {c} slots={}", nums(s));
                        }
                        let _ = writeln!(
                            out,
                            "  block={} size={}",
                            leaf_list(block),
                            lay.boxed_block_size(ty).unwrap_or(0)
                        );
                    }
                    None => {}
                }
                for (c, case) in lay.alt_fields(*a).iter().enumerate() {
                    for (i, (fty, idx)) in case.iter().enumerate() {
                        let _ = writeln!(out, "  field {c}.{i} ty={} idx={}", fty.0, nums(idx));
                    }
                }
            }
            _ => {}
        }
    }
    for r in 0..m.type_defs.len() {
        let block = lay.type_block(ms_mir::types::TypeId(r as u32));
        let _ = writeln!(out, "block {r} {}", leaf_list(&block));
    }
    for (i, f) in m.funcs.iter().enumerate() {
        let c = lay.closure(f);
        let caps: Vec<String> = c
            .captures
            .iter()
            .map(|s| format!("{}@{}:{}", s.ty.0, s.offset, leaf_list(&s.leaves)))
            .collect();
        let _ = writeln!(out, "closure {i} size={} caps={}", c.size, caps.join(" "));
    }
}

/// Internal faults quote the interpreter's own debug output, which the C version does not copy.
fn plain(message: &str) -> &str {
    if message.starts_with("interpreter:") || message.starts_with("entry returned") {
        "interpreter"
    } else {
        message
    }
}

/// Runs the entry and prints what the C interpreter prints: the program's output, its exit code
/// or fault (kind, message, frames, cleanup faults) and the drop and step counts.
fn run_module(m: &ms_mir::ir::Module, out: &mut String) {
    if ms_mir::expand_owned::needed(m) {
        out.push_str("skip expand\n");
        return;
    }
    let mut it = Interp::new(m);
    it.set_fuel(Some(2_000_000));
    let result = it.run_entry();
    let _ = writeln!(out, "stdout={}", it.stdout().replace('\n', "\\n"));
    match result {
        Ok(code) => {
            let _ = writeln!(out, "exit {code}");
        }
        Err(f) => {
            let kind = format!("{:?}", f.kind);
            let kind = kind.split('(').next().unwrap_or("");
            let _ = writeln!(
                out,
                "fault {kind} {} fuel={}",
                plain(&f.message),
                f.fuel_exhausted as u8
            );
            for s in &f.stack {
                let _ = writeln!(out, "  at {s}");
            }
            for c in &f.cleanup_faults {
                let _ = writeln!(out, "  cleanup {}", plain(c));
            }
        }
    }
    let _ = writeln!(out, "drops {} steps {}", it.drops(), it.steps());
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
        .map(|&d| {
            if d == usize::MAX {
                "-".into()
            } else {
                d.to_string()
            }
        })
        .collect();
    let _ = writeln!(out, "idom {}", text.join(" "));
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            let res = m.result_mode(f, inst).map_or('-', mode_char);
            // `call` and `call.rt` give one mode per callee parameter, which differs from the
            // operand count in an ill-formed instruction; one mode per operand is what matters.
            let mut modes: String = ms_mir::verify::arg_modes(m, f, inst)
                .into_iter()
                .take(inst.args.len())
                .map(mode_char)
                .take(inst.args.len())
                .collect();
            while modes.len() < inst.args.len() {
                modes.push('B');
            }
            let views = u8::from(m.result_views(f, inst));
            let owned = ms_mir::verify::indirect_owned(m, f, inst);
            let _ = writeln!(
                out,
                "{bi}.{ii} res={res} views={views} owned={owned:x} args={modes}"
            );
        }
    }
}
