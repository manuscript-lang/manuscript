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
                if pass == "debug_types" {
                    out.push_str(&debug_types_dump(&m));
                    continue;
                }
                if pass == "debug_files" {
                    for f in &m.files {
                        let _ = writeln!(out, "{}", ms_mir::debug_files::debug_file_name(f));
                    }
                    continue;
                }
                if pass == "tables" {
                    let ranges: Vec<Vec<(u32, u32, u32, u32)>> = m
                        .funcs
                        .iter()
                        .map(|f| {
                            f.blocks
                                .iter()
                                .flat_map(|b| &b.insts)
                                .enumerate()
                                .map(|(k, i)| (k as u32 * 4, i.loc.file, i.loc.line, i.loc.scope))
                                .collect()
                        })
                        .collect();
                    let funcs: Vec<_> = m
                        .funcs
                        .iter()
                        .zip(&ranges)
                        .map(|(f, r)| ms_mir::fault_tables::FuncTable {
                            name: &f.name,
                            file: f.loc.file,
                            line: f.loc.line,
                            size: r.len() as u32 * 4 + 1,
                            ranges: r,
                        })
                        .collect();
                    let scopes: Vec<_> = m.funcs.iter().flat_map(|f| f.scopes.clone()).collect();
                    let built = ms_mir::fault_tables::build(&m.files, &funcs, &scopes);
                    for b in &built.blob {
                        let _ = write!(out, "{b:02x}");
                    }
                    out.push('\n');
                    for (at, to) in &built.pointers {
                        let _ = writeln!(out, "ptr {at} {to}");
                    }
                    for (at, func, off) in &built.pcs {
                        let _ = writeln!(out, "pc {at} {func} {off}");
                    }
                    continue;
                }
                if pass == "slots" {
                    for f in &m.funcs {
                        let mut v: Vec<_> =
                            ms_mir::slot_scope::confined(&m, f).into_iter().collect();
                        v.sort_unstable_by_key(|(slot, _)| slot.0);
                        let list: String = v
                            .iter()
                            .map(|(s, b)| format!(" %{}={}", s.0, b.0))
                            .collect();
                        let _ = writeln!(out, "{}:{list}", f.name);
                    }
                    continue;
                }
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

/// What `print_debug_types` in `compiler/tools/ms_mir_pass.c` prints.
fn debug_types_dump(m: &ms_mir::ir::Module) -> String {
    use ms_mir::debug_types::{DebugKind, Encoding, debug_types_by_ty};
    let (types, of_ty) = debug_types_by_ty(m);
    let mut out = String::new();
    for (i, t) in types.iter().enumerate() {
        let _ = write!(out, "{i} {} size={} ", t.name, t.size);
        let members = match &t.kind {
            DebugKind::Base(e) => {
                let e = match e {
                    Encoding::Bool => "bool",
                    Encoding::Signed => "signed",
                    Encoding::Unsigned => "unsigned",
                    Encoding::Float => "float",
                };
                let _ = writeln!(out, "base {e}");
                &[][..]
            }
            DebugKind::Pointer(to) => {
                match to {
                    Some(to) => {
                        let _ = writeln!(out, "pointer -> {to}");
                    }
                    None => out.push_str("pointer\n"),
                }
                &[][..]
            }
            DebugKind::Struct(ms) => {
                out.push_str("struct\n");
                ms
            }
            DebugKind::Union(ms) => {
                out.push_str("union\n");
                ms
            }
        };
        for mem in members {
            let _ = writeln!(out, "  {} @{}: {}", mem.name, mem.offset, mem.ty);
        }
    }
    out.push_str("of_ty");
    for i in of_ty {
        let _ = write!(out, " {i}");
    }
    out.push('\n');
    out
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
        "exit_drops" => {
            ms_mir::exit_drops::run(m);
            true
        }
        "expand" => ms_mir::expand::run(m, true),
        "expand-nochecks" => ms_mir::expand::run(m, false),
        "expand_owned" => ms_mir::expand_owned::run(m),
        "unwind" => ms_mir::unwind::run(m),
        "cancel_edges" => ms_mir::cancel_edges::run(m),
        "depth" => ms_mir::depth::lower(m),
        "glue" => ms_mir::glue::run(m),
        "debug_types" | "frames" | "copies" | "slots" | "tables" | "debug_files" => true,
        "count_ops" => {
            ms_mir::count_ops::run(m);
            true
        }
        "finish" => {
            ms_mir::unwind::run(m);
            ms_mir::cancel_edges::run(m);
            ms_mir::depth::lower(m);
            ms_mir::expand::run(m, true);
            ms_mir::glue::run_and_expand(m);
            true
        }
        "glue_expand" => {
            ms_mir::glue::run_and_expand(m);
            true
        }
        other => panic!("unknown pass {other}"),
    })
}
