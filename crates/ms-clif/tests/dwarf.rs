//! Real LLVM consumers validate native ELF, Mach-O/dSYM and COFF/PE source addresses.
//! Missing consumer tools fail the test; the six-platform gate installs them.

use ms_clif::{Options, compile, link::link};
use ms_mir::{opt, parse::parse_module, verify::verify_module};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::process::Command;

mod support;
use support::cc;

fn tool(program: &str) -> String {
    let key = if program == "llvm-dwarfdump" {
        "LLVM_DWARFDUMP"
    } else {
        "LLVM_SYMBOLIZER"
    };
    std::env::var(key).unwrap_or_else(|_| program.into())
}

fn debug_file(path: &Path) -> PathBuf {
    if let Some(bundle) = ms_clif::link::debug_companion_path(path).filter(|p| p.exists()) {
        let dir = bundle.join("Contents/Resources/DWARF");
        let files: Vec<_> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .collect();
        assert_eq!(files.len(), 1, "one linked DWARF image");
        files[0].clone()
    } else {
        path.to_owned()
    }
}

fn output(program: &str, args: &[&str], path: &Path) -> String {
    let o = Command::new(tool(program))
        .args(args)
        .arg(path)
        .output()
        .expect(program);
    assert!(
        o.status.success(),
        "{program} {args:?} {} failed ({}):\nstdout:\n{}\nstderr:\n{}",
        path.display(),
        o.status,
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    );
    assert!(
        o.stderr.is_empty(),
        "{program}: {}",
        String::from_utf8_lossy(&o.stderr)
    );
    String::from_utf8(o.stdout).unwrap()
}

fn location(path: &Path, address: &str) -> String {
    let mut command = Command::new(tool("llvm-symbolizer"));
    command.arg(format!("--obj={}", path.display())).args([
        "--functions=none",
        "--output-style=GNU",
        "--no-inlines",
    ]);
    let o = command.arg(address).output().unwrap();
    assert!(o.status.success(), "{}", String::from_utf8_lossy(&o.stderr));
    assert!(
        o.stderr.is_empty(),
        "{}",
        String::from_utf8_lossy(&o.stderr)
    );
    String::from_utf8(o.stdout)
        .unwrap()
        .trim()
        .replace('\\', "/")
}

fn check_lines(path: &Path, absolute: &Path, optimized: bool) {
    let debug = debug_file(path);
    let verified = output("llvm-dwarfdump", &["--verify"], &debug);
    assert!(verified.contains("No errors."), "{verified}");
    let info = output("llvm-dwarfdump", &["--debug-info"], &debug);
    assert!(
        info.contains("DW_AT_stmt_list") && info.contains("DW_AT_ranges"),
        "{info}"
    );
    let decoded = output("llvm-dwarfdump", &["--debug-line"], &debug);
    assert!(
        decoded.contains("Line table prologue"),
        "linked line sections missing: {decoded}"
    );
    std::fs::write(path.with_extension("lines.txt"), &decoded).unwrap();
    let mut seen = HashSet::new();
    let mut known_addresses = HashSet::new();
    let mut ends = Vec::new();
    let mut previous_line = None;
    let mut interior_end = None;
    let mut resumed = None;
    for row in decoded.lines() {
        let cells: Vec<_> = row.split_whitespace().collect();
        if cells.len() < 4 || !cells[0].starts_with("0x") {
            continue;
        }
        let address = cells[0];
        if cells.contains(&"end_sequence") {
            ends.push(address.to_string());
            if previous_line == Some(12) {
                interior_end = Some(address.to_string());
            }
            continue;
        }
        let Ok(line) = cells[1].parse::<u32>() else {
            continue;
        };
        let got = location(path, address);
        let suffix = match line {
            10 | 12 => format!("{}:{line}", absolute.display()).replace('\\', "/"),
            30 | 31 | 40 => format!("relative/nested/first.ms:{line}"),
            70 => "inline/origin.ms:70".into(),
            90 => "relative/nested/first.ms:90".into(),
            _ => panic!("unexpected line {line}: {row}"),
        };
        assert!(
            got.ends_with(&suffix),
            "{} {}: {got}, wanted {suffix}",
            path.display(),
            address
        );
        seen.insert(line);
        previous_line = Some(line);
        if line == 40 {
            resumed = Some(address.to_string());
        }
        known_addresses.insert(address.to_string());
    }
    assert!(
        seen.contains(&12) && seen.contains(&30),
        "multiple functions/files: {decoded}"
    );
    if optimized {
        assert!(seen.contains(&70), "inlined source origin: {decoded}");
    }
    let interior_end = interior_end.expect("known span before internal gap");
    let resumed = resumed.expect("known span after internal gap");
    let pc = |s: &str| u64::from_str_radix(s.trim_start_matches("0x"), 16).unwrap();
    assert!(
        pc(&resumed) > pc(&interior_end) + 1,
        "internal gap must contain code"
    );
    let inside = location(path, &format!("0x{:x}", pc(&interior_end) + 1));
    assert!(
        inside.ends_with(":?") || inside.ends_with(":0"),
        "internal gap: {inside}"
    );
    // End rows without a new known row at the same PC bound an unknown gap or
    // the function end. A previous line must not leak across that boundary.
    let gaps: Vec<_> = ends
        .iter()
        .filter(|pc| !known_addresses.contains(*pc))
        .collect();
    assert!(!gaps.is_empty(), "expected sequence boundaries: {decoded}");
    for pc in gaps {
        let got = location(path, pc);
        // A consumer may report a fallback filename, but there must be
        // no source line at this boundary.
        assert!(
            got.ends_with(":?") || got.ends_with(":0"),
            "gap {pc}: {got}"
        );
    }
}

#[test]
fn dwarf_lines_resolve_object_and_linked_executable_with_and_without_optimization() {
    let d: PathBuf = std::env::temp_dir().join(format!("ms-dwarf-{}", std::process::id()));
    std::fs::create_dir_all(d.join("source directory")).unwrap();
    let absolute = d.join("source directory/first.ms");
    std::fs::write(&absolute, "# source attribution fixture\n".repeat(100)).unwrap();
    let relative =
        PathBuf::from(".artifacts").join(format!("dwarf-sources-{}", std::process::id()));
    let second = relative.join("relative/nested/first.ms");
    let origin = relative.join("inline/origin.ms");
    for path in [&second, &origin] {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, "# source attribution fixture\n".repeat(100)).unwrap();
    }
    let src = format!(
        r#"module "lines"
file 0 {:?}
file 1 {:?}
file 2 {:?}
file 3 ""
entry @main
extern @msrt_print_int(int)
fn @origin(%x: int) -> int inline(always) !2:69:1 {{
b0:
  %one: int = iconst 1
  %r: int = iadd %x, %one !2:70:3
  ret %r
}}
fn @first(%x: int) -> int export inline(never) !0:9:1 {{
b0:
  %r: int = call @origin(%x) !0:10:3
  %u: unit = call.rt @msrt_print_int(%r) !0:12:3
  %unknown: unit = call.rt @msrt_print_int(%r)
  %invalid: unit = call.rt @msrt_print_int(%r) !3:123:1
  %again: unit = call.rt @msrt_print_int(%r) !1:40:3
  ret %r
}}
fn @second(%y: int) -> int export inline(never) !1:29:1 {{
b0:
  %r: int = call @first(%y) !1:30:3
  %two: int = iconst 2
  %v: int = imul %r, %two !1:31:3
  ret %v
}}
fn @main() -> int !1:89:1 {{
b0:
  %x: int = iconst 41
  %r: int = call @second(%x) !1:90:3
  %z: int = iconst 0
  ret %z
}}
"#,
        absolute.to_str().unwrap(),
        second.to_str().unwrap(),
        origin.to_str().unwrap()
    );
    let runtime = d.join("testrt.o");
    let c = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/rt/testrt.c");
    assert!(
        cc().args(["-O1", "-c", "-fno-omit-frame-pointer", "-o"])
            .arg(&runtime)
            .arg(c)
            .status()
            .unwrap()
            .success()
    );
    for optimized in [false, true] {
        let mut m = parse_module(&src).unwrap();
        verify_module(&m).unwrap();
        if optimized {
            opt::optimize(&mut m, opt::Level::Speed, true);
        }
        let opts = Options {
            opt_level: if optimized { "speed" } else { "none" },
            ..Options::default()
        };
        let bytes = compile(&m, &opts).unwrap();
        assert_eq!(bytes, compile(&m, &opts).unwrap(), "deterministic DWARF");
        let obj = d.join(format!("lines-{optimized}.o"));
        std::fs::write(&obj, bytes).unwrap();
        check_lines(&obj, &absolute, optimized);
        let exe = d.join(format!("lines-{optimized}{}", std::env::consts::EXE_SUFFIX));
        link(&obj, &runtime, &exe).unwrap();
        let out = Command::new(&exe).output().unwrap();
        assert_eq!(out.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&out.stdout).replace("\r\n", "\n"),
            "42\n42\n42\n42\n"
        );
        check_lines(&exe, &absolute, optimized);
    }
    eprintln!("DWARF consumer artifacts: {}", d.display());
    std::fs::remove_dir_all(relative).unwrap();
}

#[test]
fn unknown_or_invalid_source_paths_do_not_invent_lines() {
    let mut m =
        parse_module("module \"unknown\"\nfn @f(%x: int) -> int {\nb0:\n ret %x\n}\n").unwrap();
    for files in [
        vec![],
        vec!["".into()],
        vec!["bad\0path".into()],
        vec!["known.ms".into()],
    ] {
        m.files = files;
        let bytes = compile(&m, &Options::default()).unwrap();
        let d = std::env::temp_dir().join(format!("ms-dwarf-unknown-{}.o", std::process::id()));
        std::fs::write(&d, bytes).unwrap();
        assert!(!output("llvm-dwarfdump", &["--debug-line"], &d).contains("Line table prologue"));
    }
}
