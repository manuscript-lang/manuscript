//! Differential tests: MIR text is run by the reference interpreter and, compiled
//! natively with the test runtime, must produce the same output and exit status.

use ms_clif::{compile, link::link, Options};
use ms_mir::interp::Interp;
use ms_mir::parse::parse_module;
use ms_mir::verify::verify_module;
use std::path::PathBuf;
use std::process::Command;
use std::sync::OnceLock;

fn dir() -> PathBuf {
    let d = std::env::temp_dir().join(format!("ms-clif-tests-{}", std::process::id()));
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Builds the test runtime once and returns the path of its object file.
fn runtime() -> &'static PathBuf {
    static RT: OnceLock<PathBuf> = OnceLock::new();
    RT.get_or_init(|| {
        let out = dir().join("testrt.o");
        let src = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/rt/testrt.c");
        let st = Command::new("cc").args(["-O1", "-c", "-fno-omit-frame-pointer", "-o"]).arg(&out).arg(src).status().expect("cc");
        assert!(st.success());
        out
    })
}

pub struct Outcome {
    pub stdout: String,
    pub code: i32,
}

fn module(src: &str) -> ms_mir::ir::Module {
    let m = parse_module(src).unwrap_or_else(|e| panic!("{e}"));
    verify_module(&m).unwrap_or_else(|e| panic!("{e:#?}"));
    m
}

pub fn run_interp(src: &str) -> Outcome {
    let m = module(src);
    let mut it = Interp::new(&m);
    let r = it.run_entry();
    let code = match r {
        Ok(v) => v as i32,
        Err(_) => 70,
    };
    Outcome { stdout: it.stdout().to_string(), code }
}

pub fn run_native_with(src: &str, opts: &Options, tag: &str) -> Outcome {
    let m = module(src);
    let obj = compile(&m, opts).unwrap_or_else(|e| panic!("{e}"));
    let d = dir();
    let objp = d.join(format!("{tag}.o"));
    std::fs::write(&objp, obj).unwrap();
    let exe = d.join(tag);
    link(&objp, runtime(), &exe).unwrap_or_else(|e| panic!("{e}"));
    let out = Command::new(&exe).output().expect("run");
    Outcome { stdout: String::from_utf8_lossy(&out.stdout).into_owned(), code: out.status.code().unwrap_or(-1) }
}

pub fn run_native(src: &str, tag: &str) -> Outcome {
    run_native_with(src, &Options::default(), tag)
}

pub fn same(src: &str, tag: &str) -> Outcome {
    let a = run_interp(src);
    let b = run_native(src, tag);
    assert_eq!(a.stdout, b.stdout, "stdout differs ({tag})");
    assert_eq!(a.code, b.code, "exit code differs ({tag})");
    b
}

#[test]
fn sum_loop() {
    let src = r#"module "sum"
entry @main
fn @sum(%n: int) -> int {
b0:
  %z: int = iconst 0
  br b1(%z, %z)
b1(%i: int, %acc: int):
  %c: bool = icmp.lt %i, %n
  br_if %c, b2(), b3()
b2:
  %a: int = iadd.chk %acc, %i
  %one: int = iconst 1
  %j: int = iadd %i, %one
  br b1(%j, %a)
b3:
  ret %acc
}
fn @main() -> int {
b0:
  %n: int = iconst 100
  %r: int = call @sum(%n)
  %k: int = iconst 7
  %m: int = srem.chk %r, %k
  ret %m
}
"#;
    let o = same(src, "sum_loop");
    assert_eq!(o.code, 4950 % 7);
}
