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

/// Frames of functions the optimizer inlined still appear in fault traces.
#[test]
fn fault_trace_shows_inlined_frames() {
    let src = r#"module "trace"
entry @main
file 0 "t.ms"
fn @limit() -> int !0:5:1 {
b0:
  %a: int = iconst 1
  %z: int = iconst 0 !0:6:3
  %q: int = sdiv.chk %a, %z !0:6:12
  ret %q
}
fn @probe() -> int !0:7:1 {
b0:
  %r: int = call @limit() !0:8:10
  ret %r
}
fn @main() -> int !0:11:1 {
b0:
  %r: int = call @probe() !0:12:5
  ret %r
}
"#;
    let mut m = module(src);
    ms_mir::opt::optimize(&mut m, ms_mir::opt::Level::Speed, true);
    assert_eq!(m.funcs.len(), 1, "limit and probe inline into main");
    let obj = compile(&m, &Options::default()).unwrap();
    let d = dir();
    let objp = d.join("inl_trace.o");
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
    let exe = d.join("inl_trace");
    ms_clif::link::link_all(&objp, &[&shim, real_runtime()], &exe).unwrap();
    let out = Command::new(&exe).output().unwrap();
    let err = String::from_utf8_lossy(&out.stderr);
    let at: Vec<&str> = err.lines().filter(|l| l.contains("  at ")).collect();
    assert_eq!(
        at,
        [
            "  at t.ms:6 in limit",
            "  at t.ms:8 in probe",
            "  at t.ms:12 in main"
        ],
        "{err}"
    );
}

// ---- random-program differential fuzzer -----------------------------------

struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
    fn chance(&mut self, pct: usize) -> bool {
        self.below(100) < pct
    }
}

/// Emits one random function body as MIR text. Values are SSA names; `scope` holds
/// the names visible at the current point (everything defined on the dominating path).
struct Gen {
    rng: Rng,
    out: String,
    n: usize,
    blocks: usize,
}

impl Gen {
    fn fresh(&mut self) -> String {
        self.n += 1;
        format!("%v{}", self.n)
    }

    fn block(&mut self) -> String {
        self.blocks += 1;
        format!("k{}", self.blocks)
    }

    fn pick(&mut self, scope: &[String]) -> String {
        scope[self.rng.below(scope.len())].clone()
    }

    fn konst(&mut self, scope: &mut Vec<String>) {
        const EDGE: [i64; 10] = [0, 1, -1, 2, 3, 7, 100, i64::MAX, i64::MIN, 1 << 32];
        let v = if self.rng.chance(60) {
            EDGE[self.rng.below(EDGE.len())]
        } else {
            self.rng.below(2001) as i64 - 1000
        };
        let n = self.fresh();
        self.out.push_str(&format!("  {n}: int = iconst {v}\n"));
        scope.push(n);
    }

    fn stmt(&mut self, scope: &mut Vec<String>, list: Option<&str>) {
        const BIN: [&str; 13] = [
            "iadd", "isub", "imul", "iadd.chk", "isub.chk", "imul.chk", "sdiv.chk", "srem.chk",
            "and", "or", "xor", "iadd", "isub",
        ];
        match self.rng.below(10) {
            0 => self.konst(scope),
            1 => {
                let (a, b) = (self.pick(scope), self.pick(scope));
                let cc = ["lt", "le", "gt", "ge", "eq", "ne"][self.rng.below(6)];
                let c = self.fresh();
                self.out
                    .push_str(&format!("  {c}: bool = icmp.{cc} {a}, {b}\n"));
                let (x, y) = (self.pick(scope), self.pick(scope));
                let r = self.fresh();
                self.out
                    .push_str(&format!("  {r}: int = select {c}, {x}, {y}\n"));
                scope.push(r);
            }
            2 => {
                let a = self.pick(scope);
                let r = self.fresh();
                let sh = self.rng.below(60);
                let k = self.fresh();
                self.out.push_str(&format!("  {k}: int = iconst {sh}\n"));
                let op = ["shl", "sshr"][self.rng.below(2)];
                self.out.push_str(&format!("  {r}: int = {op} {a}, {k}\n"));
                scope.push(r);
            }
            3 if list.is_some() => {
                let l = list.unwrap();
                let i = if self.rng.chance(85) {
                    let a = self.pick(scope);
                    let m = self.fresh();
                    self.out.push_str(&format!("  {m}: int = iconst 3\n"));
                    let r = self.fresh();
                    self.out.push_str(&format!("  {r}: int = and {a}, {m}\n"));
                    r
                } else {
                    self.pick(scope)
                };
                let r = self.fresh();
                self.out
                    .push_str(&format!("  {r}: int = list.get {l}, {i}\n"));
                scope.push(r);
            }
            4 => {
                // Constant operand forms the optimizer likes to rewrite.
                let a = self.pick(scope);
                let k = self.fresh();
                let kv = [2, 3, 4, 8, 16, 7, 10][self.rng.below(7)];
                self.out.push_str(&format!("  {k}: int = iconst {kv}\n"));
                let op =
                    ["imul", "sdiv.chk", "srem.chk", "imul.chk", "srem", "sdiv"][self.rng.below(6)];
                let r = self.fresh();
                self.out.push_str(&format!("  {r}: int = {op} {a}, {k}\n"));
                scope.push(r);
            }
            _ => {
                let (a, b) = (self.pick(scope), self.pick(scope));
                let op = BIN[self.rng.below(BIN.len())];
                let r = self.fresh();
                self.out.push_str(&format!("  {r}: int = {op} {a}, {b}\n"));
                scope.push(r);
            }
        }
    }

    /// Emits random code into the current block; returns the block label of the open
    /// block (where the caller continues) and leaves `scope` extended.
    fn region(&mut self, scope: &mut Vec<String>, list: Option<&str>, depth: usize, budget: usize) {
        for _ in 0..budget {
            match self.rng.below(12) {
                0 if depth < 2 => self.diamond(scope, list, depth),
                1 if depth < 2 => self.counted_loop(scope, list, depth),
                _ => self.stmt(scope, list),
            }
        }
    }

    fn diamond(&mut self, scope: &mut Vec<String>, list: Option<&str>, depth: usize) {
        let (a, b) = (self.pick(scope), self.pick(scope));
        let c = self.fresh();
        self.out
            .push_str(&format!("  {c}: bool = icmp.lt {a}, {b}\n"));
        let (t, e, j) = (self.block(), self.block(), self.block());
        self.out
            .push_str(&format!("  br_if {c}, {t}(), {e}()\n{t}:\n"));
        let mut ts = scope.clone();
        self.region(&mut ts, list, depth + 1, 3);
        let tv = self.pick(&ts);
        let (tm, em) = (self.block(), self.block());
        self.out
            .push_str(&format!("  br {tm}()\n{tm}:\n  br {j}({tv})\n{e}:\n"));
        let mut es = scope.clone();
        self.region(&mut es, list, depth + 1, 3);
        let ev = self.pick(&es);
        self.out
            .push_str(&format!("  br {em}()\n{em}:\n  br {j}({ev})\n"));
        let r = self.fresh();
        self.out.push_str(&format!("{j}({r}: int):\n"));
        scope.push(r);
    }

    fn counted_loop(&mut self, scope: &mut Vec<String>, list: Option<&str>, depth: usize) {
        let n = 1 + self.rng.below(6);
        let (zero, lim, init) = (self.fresh(), self.fresh(), self.pick(scope));
        self.out.push_str(&format!(
            "  {zero}: int = iconst 0\n  {lim}: int = iconst {n}\n"
        ));
        let (h, body, done, latch) = (self.block(), self.block(), self.block(), self.block());
        let (i, acc, ni) = (self.fresh(), self.fresh(), self.fresh());
        self.out.push_str(&format!(
            "  br {h}({zero}, {init})\n{h}({i}: int, {acc}: int):\n  poll\n"
        ));
        let c = self.fresh();
        self.out.push_str(&format!(
            "  {c}: bool = icmp.lt {i}, {lim}\n  br_if {c}, {body}(), {done}()\n{body}:\n"
        ));
        let mut bs = scope.clone();
        bs.push(i.clone());
        bs.push(acc.clone());
        self.region(&mut bs, list, depth + 1, 3);
        let nv = self.pick(&bs);
        let one = self.fresh();
        self.out.push_str(&format!(
            "  br {latch}()\n{latch}:\n  {one}: int = iconst 1\n  {ni}: int = iadd {i}, {one}\n"
        ));
        let mix = self.fresh();
        self.out.push_str(&format!(
            "  {mix}: int = iadd {acc}, {nv}\n  br {h}({ni}, {mix})\n{done}:\n"
        ));
        scope.push(acc);
    }
}

fn random_program(seed: u64) -> String {
    let mut g = Gen {
        rng: Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1),
        out: String::new(),
        n: 0,
        blocks: 0,
    };
    let mut src = String::from("module \"fz\"\nentry @main\nextern @msrt_print_int(int)\n");
    // f(a, b): random body over two params and a 4-element list.
    g.out.push_str("fn @f(%a: int, %b: int) -> int {\nb0:\n");
    let mut scope = vec!["%a".to_string(), "%b".to_string()];
    g.konst(&mut scope);
    let items: Vec<String> = (0..4).map(|_| g.pick(&scope)).collect();
    g.out.push_str(&format!(
        "  %lst: list<int> = list.lit {}\n",
        items.join(", ")
    ));
    g.region(&mut scope, Some("%lst"), 0, 14);
    let r = g.pick(&scope);
    g.out.push_str(&format!("  drop %lst\n  ret {r}\n}}\n"));
    src.push_str(&g.out);
    let (x, y) = (
        g.rng.below(2001) as i64 - 1000,
        g.rng.below(2001) as i64 - 1000,
    );
    src.push_str(&format!(
        "fn @main() -> int {{\nb0:\n  %x: int = iconst {x}\n  %y: int = iconst {y}\n  %r: int = call @f(%x, %y)\n  %u: unit = call.rt @msrt_print_int (%r)\n  %z: int = iconst 0\n  ret %z\n}}\n"
    ));
    src
}

#[test]
fn random_programs_agree() {
    let n: u64 = std::env::var("FUZZ_N")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(40);
    let first: u64 = std::env::var("FUZZ_SEED")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(1);
    let mut bad = Vec::new();
    for seed in first..first + n {
        let src = random_program(seed);
        let r = std::panic::catch_unwind(|| {
            let a = run_interp(&src);
            let b = run_native(&src, &format!("fz{seed}"));
            let c = run_native(&src, &format!("fz{seed}.opt"));
            if std::env::var("FUZZ_VERBOSE").is_ok() {
                eprintln!("seed {seed}: exit {} out {:?}", a.code, a.stdout.trim());
            }
            assert_eq!((&a.stdout, a.code), (&b.stdout, b.code), "native");
            assert_eq!((&a.stdout, a.code), (&c.stdout, c.code), "optimized");
        });
        if r.is_err() {
            std::fs::write(std::env::temp_dir().join(format!("fz{seed}.mir")), &src).ok();
            bad.push(seed);
        }
    }
    assert!(
        bad.is_empty(),
        "disagreeing seeds (sources in the temp dir): {bad:?}"
    );
}
