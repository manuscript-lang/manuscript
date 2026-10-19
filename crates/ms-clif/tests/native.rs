//! Differential tests: MIR text is run by the reference interpreter and, compiled
//! natively with the test runtime, must produce the same output and exit status.

use ms_clif::{Options, compile, link::link};
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
        let st = Command::new("cc")
            .args(["-O1", "-c", "-fno-omit-frame-pointer", "-o"])
            .arg(&out)
            .arg(src)
            .status()
            .expect("cc");
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
        Ok(v) if (0..=125).contains(&v) => v as i32,
        Ok(_) => 70,
        Err(_) => 70,
    };
    Outcome {
        stdout: it.stdout().to_string(),
        code,
    }
}

pub fn run_native_with(src: &str, opts: &Options, tag: &str) -> Outcome {
    run_native_full(src, opts, tag).0
}

/// Like [`run_native_with`], also returning stderr.
pub fn run_native_full(src: &str, opts: &Options, tag: &str) -> (Outcome, String) {
    let mut m = module(src);
    if tag.ends_with(".opt") {
        ms_mir::opt::optimize(&mut m, ms_mir::opt::Level::Speed, true);
    }
    let obj = compile(&m, opts).unwrap_or_else(|e| panic!("{e}"));
    let d = dir();
    let objp = d.join(format!("{tag}.o"));
    std::fs::write(&objp, obj).unwrap();
    let exe = d.join(tag);
    link(&objp, runtime(), &exe).unwrap_or_else(|e| panic!("{e}"));
    let out = Command::new(&exe)
        .env("MSRT_LEAKCHECK", "1")
        .output()
        .expect("run");
    let o = Outcome {
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        code: out.status.code().unwrap_or(-1),
    };
    (o, String::from_utf8_lossy(&out.stderr).into_owned())
}

pub fn run_native(src: &str, tag: &str) -> Outcome {
    run_native_with(src, &Options::default(), tag)
}

pub fn same(src: &str, tag: &str) -> Outcome {
    let a = run_interp(src);
    let b = run_native(src, tag);
    assert_eq!(a.stdout, b.stdout, "stdout differs ({tag})");
    assert_eq!(a.code, b.code, "exit code differs ({tag})");
    let c = run_native(src, &format!("{tag}.opt"));
    assert_eq!(
        a.stdout, c.stdout,
        "stdout differs after optimization ({tag})"
    );
    assert_eq!(
        a.code, c.code,
        "exit code differs after optimization ({tag})"
    );
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

/// Every fixture shared with the interpreter tests must agree natively.
#[test]
fn shared_fixtures() {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../ms-mir/tests/fixtures");
    let mut names: Vec<_> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "mir"))
        .collect();
    names.sort();
    let mut failures = Vec::new();
    for p in names {
        let src = std::fs::read_to_string(&p).unwrap();
        let tag = p.file_stem().unwrap().to_string_lossy().into_owned();
        let r = std::panic::catch_unwind(|| same(&src, &tag));
        if r.is_err() {
            failures.push(tag);
        }
    }
    assert!(failures.is_empty(), "fixtures failed: {failures:?}");
}

fn kernel_src(name: &str) -> String {
    std::fs::read_to_string(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("kernels")
            .join(format!("{name}.mir")),
    )
    .unwrap()
}

fn check_kernel(name: &str, expect: &str) {
    for tag in [name.to_string(), format!("{name}.opt")] {
        let o = run_native(&kernel_src(name), &tag);
        assert_eq!(o.code, 0, "{tag} exit code");
        assert_eq!(o.stdout.trim(), expect, "{tag} checksum");
    }
}

macro_rules! kernel_test {
    ($($name:ident => $expect:expr),* $(,)?) => {
        $(
            #[test]
            fn $name() {
                check_kernel(stringify!($name), $expect);
            }
        )*
    };
}

kernel_test! {
    collatz => "524",
    sieve => "348513",
    trees => "2621420",
    matmul => "26666000000",
    life => "204",
    nbody => "1199426",
}

#[test]
fn fault_trace_names_functions_and_lines() {
    let src = r#"module "trace"
entry @main
file 0 "t.ms"
fn @inner(%i: int) -> int !0:10:1 {
b0:
  %a: int = iconst 1
  %l: list<int> = list.lit %a !0:11:3
  %x: int = list.get %l, %i !0:12:5
  drop %l
  ret %x
}
fn @main() -> int !0:20:1 {
b0:
  %i: int = iconst 5
  %r: int = call @inner(%i) !0:21:7
  ret %r
}
"#;
    let (o, err) = run_native_full(src, &Options::default(), "trace");
    assert_eq!(o.code, 70);
    assert!(err.contains("at inner t.ms:12"), "{err}");
    assert!(err.contains("at main t.ms:21"), "{err}");
}

/// Builds the real `ms-rt` static library once (in its own target directory).
fn real_runtime() -> &'static PathBuf {
    static RT: OnceLock<PathBuf> = OnceLock::new();
    RT.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
        let target = root.join("target").join("ms-rt-for-clif");
        let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
        let st = Command::new(cargo)
            .current_dir(&root)
            .args(["build", "--release", "-p", "ms-rt", "--target-dir"])
            .arg(&target)
            .status()
            .expect("cargo build ms-rt");
        assert!(st.success(), "building ms-rt failed");
        target.join("release/libms_rt.a")
    })
}

/// Compiles `src` and links it with the real runtime plus the print shim.
fn run_real(src: &str, opt: bool, tag: &str) -> Outcome {
    let mut m = module(src);
    if opt {
        ms_mir::opt::optimize(&mut m, ms_mir::opt::Level::Speed, true);
    }
    let obj = compile(&m, &Options::default()).unwrap_or_else(|e| panic!("{e}"));
    let d = dir();
    let objp = d.join(format!("{tag}.o"));
    std::fs::write(&objp, obj).unwrap();
    let shim = d.join("printshim.o");
    let c = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/rt/printshim.c");
    let st = Command::new("cc")
        .args(["-O1", "-c", "-o"])
        .arg(&shim)
        .arg(c)
        .status()
        .expect("cc");
    assert!(st.success());
    let exe = d.join(tag);
    ms_clif::link::link_all(&objp, &[&shim, real_runtime()], &exe)
        .unwrap_or_else(|e| panic!("{e}"));
    let out = Command::new(&exe).output().expect("run");
    Outcome {
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        code: out.status.code().unwrap_or(-1),
    }
}

#[test]
fn kernels_on_real_runtime() {
    for (name, expect) in [
        ("collatz", "524"),
        ("sieve", "348513"),
        ("trees", "2621420"),
        ("matmul", "26666000000"),
        ("life", "204"),
        ("nbody", "1199426"),
        ("map_count", "5003"),
    ] {
        for opt in [false, true] {
            let o = run_real(&kernel_src(name), opt, &format!("real_{name}_{opt}"));
            assert_eq!(o.code, 0, "{name} opt={opt} exit code");
            assert_eq!(o.stdout.trim(), expect, "{name} opt={opt} checksum");
        }
    }
}

#[test]
fn fault_trace_on_real_runtime() {
    let src = r#"module "trace"
entry @main
file 0 "t.ms"
fn @inner(%i: int) -> int !0:10:1 {
b0:
  %a: int = iconst 1
  %l: list<int> = list.lit %a !0:11:3
  %x: int = list.get %l, %i !0:12:5
  drop %l
  ret %x
}
fn @main() -> int !0:20:1 {
b0:
  %i: int = iconst 5
  %r: int = call @inner(%i) !0:21:7
  ret %r
}
"#;
    let m = module(src);
    let obj = compile(&m, &Options::default()).unwrap();
    let d = dir();
    let objp = d.join("real_trace.o");
    std::fs::write(&objp, obj).unwrap();
    let shim = d.join("printshim.o");
    let c = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/rt/printshim.c");
    assert!(
        Command::new("cc")
            .args(["-O1", "-c", "-o"])
            .arg(&shim)
            .arg(c)
            .status()
            .unwrap()
            .success()
    );
    let exe = d.join("real_trace");
    ms_clif::link::link_all(&objp, &[&shim, real_runtime()], &exe).unwrap();
    let out = Command::new(&exe).output().unwrap();
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(err.contains("index"), "{err}");
    assert!(err.contains("inner") && err.contains("t.ms:12"), "{err}");
    assert!(err.contains("main") && err.contains("t.ms:21"), "{err}");
}
