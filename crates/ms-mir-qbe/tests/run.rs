//! Compiles MIR text through QBE with the system C compiler and runs the program.

use ms_mir::parse::parse_module;
use std::path::{Path, PathBuf};
use std::process::Command;

fn run(c: &mut Command) {
    let out = c.output().expect("tool starts");
    assert!(
        out.status.success(),
        "{c:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
}

/// QBE built from the vendored sources.
fn qbe(dir: &Path) -> PathBuf {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../runtime/third_party/qbe");
    let bin = dir.join("qbe");
    let mut c = Command::new("cc");
    c.args(["-std=c99", "-O1", "-w", "-I"]).arg(&root);
    for sub in ["", "amd64", "arm64", "rv64"] {
        let d = root.join(sub);
        for e in std::fs::read_dir(d).unwrap() {
            let p = e.unwrap().path();
            if p.extension().is_some_and(|x| x == "c") {
                c.arg(p);
            }
        }
    }
    run(c.arg("-o").arg(&bin));
    bin
}

/// QBE's name for the host target.
fn target() -> &'static str {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("macos", "aarch64") => "arm64_apple",
        ("macos", _) => "amd64_apple",
        ("windows", _) => "amd64_win",
        (_, "aarch64") => "arm64",
        _ => "amd64_sysv",
    }
}

/// Builds `src` with `@main`'s result as the exit status and returns that status.
fn exit_status(name: &str, src: &str) -> i32 {
    let dir = std::env::temp_dir().join(format!("ms-mir-qbe-{name}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let module = parse_module(src).expect("parses");
    let ssa = ms_mir_qbe::emit(&module).unwrap_or_else(|e| panic!("{e}"));
    std::fs::write(dir.join("p.ssa"), &ssa).unwrap();
    let qbe = qbe(&dir);
    let asm = Command::new(&qbe)
        .args(["-t", target()])
        .arg(dir.join("p.ssa"))
        .output()
        .unwrap();
    assert!(
        asm.status.success(),
        "{ssa}\n{}",
        String::from_utf8_lossy(&asm.stderr)
    );
    std::fs::write(dir.join("p.s"), &asm.stdout).unwrap();
    std::fs::write(
        dir.join("rt.c"),
        "#include <stdlib.h>\nextern long msmain(void);\n\
         void msrt_fault_int_overflow(void){ exit(134); }\nint main(void){ return (int)msmain(); }\n",
    )
    .unwrap();
    run(Command::new("cc")
        .arg(dir.join("p.s"))
        .arg(dir.join("rt.c"))
        .arg("-o")
        .arg(dir.join("p")));
    Command::new(dir.join("p"))
        .status()
        .unwrap()
        .code()
        .unwrap()
}

#[test]
fn arithmetic_loop_and_calls() {
    let src = r#"module "t"
file 0 "t.ms"
entry @msmain

fn @sq(%x: int) -> int {
b0:
  %r: int = imul %x, %x
  ret %r
}

fn @msmain() -> int {
b0:
  %z: int = iconst 0
  %n: int = iconst 5
  br b1(%z, %z)
b1(%i: int, %acc: int):
  %c: bool = icmp.lt %i, %n
  br_if %c, b2(), b3()
b2:
  %s: int = call @sq(%i)
  %a: int = iadd.chk %acc, %s
  %one: int = iconst 1
  %j: int = iadd.chk %i, %one
  br b1(%j, %a)
b3:
  ret %acc
}
"#;
    // 0 + 1 + 4 + 9 + 16
    assert_eq!(exit_status("loop", src), 30);
}

#[test]
fn checked_add_faults_on_overflow() {
    let src = r#"module "t"
file 0 "t.ms"
entry @msmain

fn @msmain() -> int {
b0:
  %m: int = iconst 9223372036854775807
  %one: int = iconst 1
  %r: int = iadd.chk %m, %one
  ret %r
}
"#;
    assert_eq!(exit_status("overflow", src), 134);
}
