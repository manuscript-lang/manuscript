//! The Rust engine end to end: load, check, an injected lowering, Cranelift,
//! link, run. Lowering from the typed HIR is a separate workstream, so the
//! tests supply the MIR the lowering would produce.

// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_rt as _;
use std::path::{Path, PathBuf};
use std::process::Command;

use ms_build::{Lower, Module, Native};
use ms_cli::backend::Io;
use ms_cli::engine::Engine;

/// A lowering that ignores the program and returns fixed MIR.
struct Fixed(&'static str);

impl Lower for Fixed {
    fn lower(&self, _: &ms_check::Program, _: &str) -> Result<Module, String> {
        ms_mir::parse::parse_module(self.0).map_err(|e| e.to_string())
    }
}

const EXIT_SEVEN: &str =
    "module \"t\"\nentry @main\nfn @main() -> int {\nb0:\n  %c: int = iconst 7\n  ret %c\n}\n";

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ms-engine-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn ms<L: Lower>(backend: &Engine<L>, args: &[&str]) -> (i32, String, String) {
    let args: Vec<String> = args.iter().map(|a| a.to_string()).collect();
    let (mut out, mut err) = (Vec::new(), Vec::new());
    let status = {
        let mut input: &[u8] = &[];
        let mut io = Io {
            stdin: &mut input,
            stdout: &mut out,
            stderr: &mut err,
        };
        ms_cli::run(&args, backend, &mut io)
    };
    (
        status,
        String::from_utf8_lossy(&out).into_owned(),
        String::from_utf8_lossy(&err).into_owned(),
    )
}

fn write(dir: &Path, name: &str, text: &str) -> String {
    let path = dir.join(name);
    std::fs::write(&path, text).unwrap();
    path.to_string_lossy().into_owned()
}

const MAIN: &str = "export def main() -> Int:\n    return 0\n";

#[test]
fn run_returns_the_program_status() {
    let dir = scratch("run");
    let source = write(&dir, "main.ms", MAIN);
    let backend = Engine::new(Fixed(EXIT_SEVEN));
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!((status, err.as_str()), (7, ""));
}

#[test]
fn build_writes_an_executable_and_reports_it() {
    let dir = scratch("build");
    let source = write(&dir, "main.ms", MAIN);
    let out = dir.join("prog");
    let backend = Engine::new(Fixed(EXIT_SEVEN));
    let (status, stdout, err) = ms(&backend, &["build", &source, "-o", out.to_str().unwrap()]);
    assert_eq!(status, 0, "{err}");
    assert!(stdout.starts_with("Built "), "{stdout}");
    assert_eq!(Command::new(&out).status().unwrap().code(), Some(7));
    assert!(dir.join("prog.ms-build.json").is_file());

    let (status, json, err) = ms(
        &backend,
        &["build", &source, "-o", out.to_str().unwrap(), "--json"],
    );
    assert_eq!(status, 0, "{err}");
    for needle in [
        "\"command\": \"build\"",
        "\"completed\": true",
        "\"kind\": \"executable\"",
        "\"state\": \"verified\"",
    ] {
        assert!(json.contains(needle), "{needle} missing in {json}");
    }
}

#[test]
fn checker_diagnostics_stop_before_lowering() {
    let dir = scratch("diagnostics");
    let source = write(
        &dir,
        "main.ms",
        "export def main() -> Int:\n    return \"x\"\n",
    );
    let backend = Engine::new(Fixed(EXIT_SEVEN));
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!(status, 1);
    assert!(err.contains(": type: "), "{err}");
    assert!(err.contains("1 error; fix them and re-run"), "{err}");

    let (status, json, _) = ms(&backend, &["build", &source, "--json"]);
    assert_eq!(status, 1);
    assert!(json.contains("\"reason\": \"compile_error\""), "{json}");
    assert!(json.contains("\"phase\": \"type\""), "{json}");
}

#[test]
fn entry_must_be_an_exported_main() {
    let dir = scratch("entry");
    let backend = Engine::new(Fixed(EXIT_SEVEN));
    for (text, expected) in [
        ("def main() -> Int:\n    return 0\n", "main is not exported"),
        (
            "export def other() -> Int:\n    return 0\n",
            "no main function is declared",
        ),
        (
            "export def main(x: Int) -> Int:\n    return x\n",
            "main takes no parameters",
        ),
    ] {
        let source = write(&dir, "main.ms", text);
        let (status, _, err) = ms(&backend, &["run", &source]);
        assert_eq!(status, 1, "{text}");
        assert!(err.contains("entry must export fn main() Int; "), "{err}");
        assert!(err.contains(expected), "{expected} missing in {err}");
    }
}

#[test]
fn imports_load_in_dependency_order() {
    let dir = scratch("imports");
    write(&dir, "lib.ms", "export def one() -> Int:\n    return 1\n");
    let source = write(
        &dir,
        "main.ms",
        "from \"./lib.ms\" import one\n\nexport def main() -> Int:\n    return one()\n",
    );
    let backend = Engine::new(Fixed(EXIT_SEVEN));
    assert_eq!(ms(&backend, &["run", &source]).0, 7);

    let missing = write(
        &dir,
        "main.ms",
        "from \"./nope.ms\" import one\n\nexport def main() -> Int:\n    return 0\n",
    );
    let (status, _, err) = ms(&backend, &["run", &missing]);
    assert_eq!(status, 1);
    assert!(err.contains("cannot find module ./nope.ms"), "{err}");
}

#[test]
fn unavailable_lowering_is_a_lowering_diagnostic() {
    let dir = scratch("unavailable");
    let source = write(&dir, "main.ms", MAIN);
    let backend = Engine::new(ms_build::Unavailable);
    let (status, _, err) = ms(&backend, &["build", &source]);
    assert_eq!(status, 1);
    assert!(
        err.contains(": lowering: lowering is not available"),
        "{err}"
    );
}

#[test]
fn build_refuses_to_overwrite_source_and_directories() {
    let dir = scratch("protected");
    let source = write(&dir, "main.ms", MAIN);
    let backend = Engine::new(Fixed(EXIT_SEVEN));
    let (status, _, err) = ms(&backend, &["build", &source, "-o", &source]);
    assert_eq!(status, 2);
    assert!(err.contains("would overwrite main.ms"), "{err}");
    let (status, _, err) = ms(&backend, &["build", &source, "-o", dir.to_str().unwrap()]);
    assert_eq!(status, 2);
    assert!(err.contains("is a directory"), "{err}");
}

#[test]
fn library_projects_have_no_executable_entry() {
    let dir = scratch("library");
    std::fs::create_dir_all(dir.join("src")).unwrap();
    write(
        &dir,
        "ms.toml",
        "[project]\nname = \"lib\"\nsource = \"src\"\n",
    );
    write(
        &dir.join("src"),
        "lib.ms",
        "export def one() -> Int:\n    return 1\n",
    );
    let backend = Engine::new(Fixed(EXIT_SEVEN));
    let manifest = dir.join("ms.toml");
    let (status, _, err) = ms(&backend, &["build", manifest.to_str().unwrap()]);
    assert_eq!(status, 1);
    assert!(
        err.contains("library project has no executable entry"),
        "{err}"
    );
    assert!(!err.contains("lock"), "{err}");
}

const TESTS: &str = "from \"@std/testing.ms\" import expect_equal\n\ntest \"adds\":\n    try expect_equal(1 + 1, 2)\n\ntest \"fails\":\n    try expect_equal(1 + 1, 3)\n\ntest \"passes too\":\n    try expect_equal(2 * 2, 4)\n";

#[test]
fn native_lowering_runs_real_programs() {
    let dir = scratch("native-run");
    let source = write(
        &dir,
        "main.ms",
        "export def main() -> Int:\n    return 6 * 7 - 40\n",
    );
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!((status, err.as_str()), (2, ""));
}

/// A standard-library native outside `ms-rt` links through the embedded `ms-native` archive.
#[test]
fn native_programs_link_every_standard_library_crate() {
    let dir = scratch("native-std");
    let source = write(
        &dir,
        "main.ms",
        "from \"@std/semver.ms\" import parse, format\n\nexport def main() -> Int:\n    let v = parse(\"1.2.3\").get()\n    if format(v) == \"1.2.3\":\n        return 0\n    return 1\n",
    );
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!((status, err.as_str()), (0, ""));
}

#[test]
fn native_tests_run_one_process_each() {
    let dir = scratch("native-test");
    let source = write(&dir, "sample_test.ms", TESTS);
    let backend = Engine::new(Native);
    let (status, stdout, err) = ms(&backend, &["test", &source]);
    assert_eq!(status, 1, "{err}");
    for line in [
        "PASS sample_test.ms::adds",
        "PASS sample_test.ms::passes too",
        "FAIL sample_test.ms::fails: ",
        "3 tests, 1 failed",
    ] {
        assert!(stdout.contains(line), "{line} missing in {stdout}");
    }
    let (status, json, _) = ms(&backend, &["test", &source, "--json", "--match", "passes"]);
    assert_eq!(status, 0, "{json}");
    assert!(json.contains("\"passed\": 1"), "{json}");
}

/// A runtime fault is structured data under `--json` for `ms run` and `ms test`.
#[test]
fn runtime_fault_is_reported_as_json() {
    let dir = scratch("fault-json");
    let source = write(
        &dir,
        "boom.ms",
        "def div(a: Int, b: Int) -> Int: a / b\n\nexport def main() -> Int:\n    return div(1, 0)\n\ntest \"boom\":\n    let x = div(1, 0)\n",
    );
    let backend = Engine::new(Native);
    let (status, json, err) = ms(&backend, &["run", &source, "--json"]);
    assert_eq!(status, 67, "{err}");
    for needle in [
        "\"kind\": \"division_by_zero\"",
        "\"cleanups_ran\": true",
        "\"function\": \"div\"",
        "\"line\": 1",
    ] {
        assert!(json.contains(needle), "{needle} missing in {json}");
    }
    let (status, json, _) = ms(&backend, &["test", &source, "--json"]);
    assert_eq!(status, 1, "{json}");
    assert!(json.contains("\"kind\": \"division_by_zero\""), "{json}");
}

/// `ms test ms.toml` runs the project's `test.ms` and `*_test.ms`, not only the entry module.
#[test]
fn project_test_runs_test_files() {
    let dir = scratch("project-test");
    std::fs::create_dir_all(dir.join("src")).unwrap();
    write(
        &dir,
        "ms.toml",
        "[project]\nname = \"p\"\nsource = \"./src\"\nentry = \"./src/main.ms\"\n",
    );
    write(&dir, "src/main.ms", MAIN);
    write(
        &dir,
        "test.ms",
        "test \"top\":\n    if 1 + 1 != 2:\n        return\n",
    );
    write(
        &dir,
        "extra_test.ms",
        "test \"more\":\n    if 1 + 1 != 2:\n        return\n",
    );
    let backend = Engine::new(Native);
    let manifest = dir.join("ms.toml").to_string_lossy().into_owned();
    let (status, stdout, err) = ms(&backend, &["test", &manifest]);
    assert_eq!(status, 0, "{stdout}{err}");
    for line in ["test.ms::top", "extra_test.ms::more", "2 tests, 0 failed"] {
        assert!(stdout.contains(line), "{line} missing in {stdout}");
    }
}

/// `ms build -o` creates the output's missing parent directories.
#[test]
fn build_creates_missing_output_directories() {
    let dir = scratch("build-parents");
    let source = write(&dir, "main.ms", MAIN);
    let output = dir.join("out/nested/app");
    let backend = Engine::new(Native);
    let (status, _, err) = ms(
        &backend,
        &["build", &source, "-o", &output.to_string_lossy()],
    );
    assert_eq!((status, err.as_str()), (0, ""));
    assert!(output.is_file());
}

/// `ms emit` prints the lowered intermediate code.
#[test]
fn emit_prints_the_lowered_program() {
    let dir = scratch("emit");
    let source = write(&dir, "main.ms", MAIN);
    let backend = Engine::new(Native);
    let (status, stdout, err) = ms(&backend, &["emit", &source]);
    assert_eq!((status, err.as_str()), (0, ""));
    assert!(stdout.contains("fn @main"), "{stdout}");
}

/// Drop and copy of a long chain of a recursive alternative loop over its tail; the copy keeps
/// every payload (`Tag(n, ..)`) and the original stays intact.
#[test]
fn native_chains_copy_and_drop_iteratively() {
    let dir = scratch("native-chain");
    let source = write(
        &dir,
        "main.ms",
        "type Link:\n    case End\n    case More(next: Link)\n    case Tag(n: Int, rest: Link)\n\ndef build(n: Int) -> Link:\n    if n == 0:\n        return End\n    if n % 2 == 0:\n        return More(build(n - 1))\n    return Tag(n, build(n - 1))\n\ndef sum(l: Link, acc: Int) -> Int:\n    match l:\n        case End:\n            return acc\n        case More(r):\n            return sum(r, acc)\n        case Tag(n, r):\n            return sum(r, acc + n)\n\nexport def main() -> Int:\n    let a = build(100000)\n    let b = a.clone()\n    if sum(a, 0) != 2500000000:\n        return 1\n    if sum(b, 0) != 2500000000:\n        return 2\n    return 0\n",
    );
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!((status, err.as_str()), (0, ""));
}

/// A field of a list element, and a mutator on one, change the list in place; copies keep
/// the old value.
#[test]
fn native_list_element_places_update_the_list() {
    let dir = scratch("native-elem");
    let source = write(
        &dir,
        "main.ms",
        "type Cell:\n    n: Int\n    tag: String\n\nexport def main() -> Int:\n    var cells = [Cell(n: 1, tag: \"a\"), Cell(n: 2, tag: \"b\")]\n    let before = cells.clone()\n    cells[1].n = 9\n    cells[0].tag = \"z\"\n    var grid = [[1], [2]]\n    grid[1].append(3)\n    if cells[1].n != 9 or cells[0].tag != \"z\":\n        return 1\n    if before[1].n != 2 or before[0].tag != \"a\":\n        return 2\n    if grid[1].length() != 2:\n        return 3\n    return 0\n",
    );
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!((status, err.as_str()), (0, ""));
}

/// Labeled arguments of a native method bind by name, whatever order they are written in.
#[test]
fn native_method_labels_bind_by_name() {
    let dir = scratch("native-labels");
    let source = write(
        &dir,
        "main.ms",
        "export def main() -> Int:\n    var items = [1, 2, 3]\n    items.set(value: 8, 0)\n    items.insert(value: 5, 1)\n    if items[0] != 8 or items[1] != 5 or items.length() != 4:\n        return 1\n    return 0\n",
    );
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!((status, err.as_str()), (0, ""));
}

/// Decoding a deeply nested JSON document moves each subtree out of its `Optional` result
/// instead of deep-copying it, so the cost is linear in depth (it was quadratic: 20 000 levels
/// took 16 seconds).
#[test]
fn native_json_parse_of_deep_nesting_is_linear() {
    let dir = scratch("native-json-deep");
    let source = write(
        &dir,
        "main.ms",
        "from \"@std/json.ms\" import parse, JsonValue, JsonError\n\nexport def main() -> Int:\n    let n = 50000\n    let text = f\"{\"[\".repeat(n).get()}1{\"]\".repeat(n).get()}\"\n    let r: Result[JsonValue, JsonError] = parse(text)\n    if r.is_error():\n        return 1\n    return 0\n",
    );
    let backend = Engine::new(Native);
    let started = std::time::Instant::now();
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!((status, err.as_str()), (0, ""));
    assert!(
        started.elapsed() < std::time::Duration::from_secs(30),
        "{:?}",
        started.elapsed()
    );
}

/// A handler that sleeps parks only its own task: other requests keep being served meanwhile.
/// `time.sleep` used to block the whole scheduler, so four 500 ms requests took two seconds and
/// a quick request waited behind them.
#[test]
fn native_http_handlers_sleep_without_blocking_other_requests() {
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpStream;
    use std::process::Stdio;
    use std::time::{Duration, Instant};

    let dir = scratch("native-http-sleep");
    let source = write(
        &dir,
        "main.ms",
        "from \"@std/http.ms\" import headers, HttpRequest, HttpResponse\nfrom \"@std/net.ms\" import network\nfrom \"@std/io.ms\" import stdout\nfrom \"@std/time.ms\" import sleep, duration\n\ndef handle(request: HttpRequest) -> HttpResponse:\n    if request.path == \"/slow\":\n        sleep(duration(500000000))\n    return HttpResponse(200, headers(), request.path.to_bytes())\n\nexport def main() -> Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle):\n        with let server = acquired:\n            stdout().write(f\"{server.address()}\\n\").get()\n            stdout().flush().get()\n            let _ignored = server.wait()\n            return 0\n    return 1\n",
    );
    let exe = dir.join("server");
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["build", &source, "-o", exe.to_str().unwrap()]);
    assert_eq!(status, 0, "{err}");
    let mut child = Command::new(&exe).stdout(Stdio::piped()).spawn().unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let address = line.trim().to_string();
    let get = move |path: &'static str| {
        let address = address.clone();
        std::thread::spawn(move || {
            let mut stream = TcpStream::connect(&address).unwrap();
            write!(
                stream,
                "GET {path} HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n"
            )
            .unwrap();
            let mut reply = String::new();
            stream.read_to_string(&mut reply).unwrap();
            reply
        })
    };
    let started = Instant::now();
    let slow: Vec<_> = (0..4).map(|_| get("/slow")).collect();
    std::thread::sleep(Duration::from_millis(100));
    let quick_started = Instant::now();
    let quick = get("/quick").join().unwrap();
    let quick_took = quick_started.elapsed();
    for reply in slow {
        let reply = reply.join().unwrap();
        assert!(reply.starts_with("HTTP/1.1 200"), "{reply}");
    }
    let total = started.elapsed();
    child.kill().unwrap();
    child.wait().unwrap();
    assert!(quick.starts_with("HTTP/1.1 200"), "{quick}");
    assert!(quick_took < Duration::from_millis(300), "{quick_took:?}");
    assert!(total < Duration::from_millis(1500), "{total:?}");
}

/// Waiting for a child process used to block the whole scheduler, so four handlers that each ran
/// a 500 ms command took two seconds and a quick request waited behind them.
#[test]
fn native_http_handlers_run_commands_without_blocking_other_requests() {
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpStream;
    use std::process::Stdio;
    use std::time::{Duration, Instant};

    let dir = scratch("native-http-command");
    let source = write(
        &dir,
        "main.ms",
        "from \"@std/http.ms\" import headers, HttpRequest, HttpResponse\nfrom \"@std/net.ms\" import network\nfrom \"@std/io.ms\" import stdout\nfrom \"@std/process.ms\" import commands\n\ndef handle(request: HttpRequest) -> HttpResponse:\n    if request.path == \"/slow\":\n        let _out = commands().run(\"sleep\", [\"0.5\"])\n    return HttpResponse(200, headers(), request.path.to_bytes())\n\nexport def main() -> Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle):\n        with let server = acquired:\n            stdout().write(f\"{server.address()}\\n\").get()\n            stdout().flush().get()\n            let _ignored = server.wait()\n            return 0\n    return 1\n",
    );
    let exe = dir.join("server");
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["build", &source, "-o", exe.to_str().unwrap()]);
    assert_eq!(status, 0, "{err}");
    let mut child = Command::new(&exe).stdout(Stdio::piped()).spawn().unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let address = line.trim().to_string();
    let get = move |path: &'static str| {
        let address = address.clone();
        std::thread::spawn(move || {
            let mut stream = TcpStream::connect(&address).unwrap();
            write!(
                stream,
                "GET {path} HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n"
            )
            .unwrap();
            let mut reply = String::new();
            stream.read_to_string(&mut reply).unwrap();
            reply
        })
    };
    let started = Instant::now();
    let slow: Vec<_> = (0..4).map(|_| get("/slow")).collect();
    std::thread::sleep(Duration::from_millis(100));
    let quick_started = Instant::now();
    let quick = get("/quick").join().unwrap();
    let quick_took = quick_started.elapsed();
    for reply in slow {
        let reply = reply.join().unwrap();
        assert!(reply.starts_with("HTTP/1.1 200"), "{reply}");
    }
    let total = started.elapsed();
    child.kill().unwrap();
    child.wait().unwrap();
    assert!(quick.starts_with("HTTP/1.1 200"), "{quick}");
    assert!(quick_took < Duration::from_millis(300), "{quick_took:?}");
    assert!(total < Duration::from_millis(1500), "{total:?}");
}

/// A handler that faults used to leak its request and the fault report on every request
/// (about 1.2 KiB each), so a server answering faults slowly ate its memory.
#[cfg(target_os = "linux")]
#[test]
fn native_http_handler_faults_do_not_leak_per_request() {
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpStream;
    use std::process::Stdio;

    let dir = scratch("native-http-fault-leak");
    let source = write(
        &dir,
        "main.ms",
        "from \"@std/http.ms\" import headers, HttpRequest, HttpResponse\nfrom \"@std/net.ms\" import network\nfrom \"@std/io.ms\" import stdout\n\ndef handle(request: HttpRequest) -> HttpResponse:\n    let xs: List[Int] = []\n    let i = request.path.length()\n    return HttpResponse(200, headers(), f\"{xs[i]}\".to_bytes())\n\nexport def main() -> Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle):\n        with let server = acquired:\n            stdout().write(f\"{server.address()}\\n\").get()\n            stdout().flush().get()\n            let _ignored = server.wait()\n            return 0\n    return 1\n",
    );
    let exe = dir.join("server");
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["build", &source, "-o", exe.to_str().unwrap()]);
    assert_eq!(status, 0, "{err}");
    let mut child = Command::new(&exe)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let address = line.trim().to_string();
    let rss_kib = |pid: u32| -> u64 {
        let status = std::fs::read_to_string(format!("/proc/{pid}/status")).unwrap();
        let field = status.lines().find(|l| l.starts_with("VmRSS:")).unwrap();
        field.split_whitespace().nth(1).unwrap().parse().unwrap()
    };
    let faults = |count: usize| {
        for _ in 0..count {
            let mut stream = TcpStream::connect(&address).unwrap();
            write!(
                stream,
                "GET /fault HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n"
            )
            .unwrap();
            let mut reply = String::new();
            stream.read_to_string(&mut reply).unwrap();
            assert!(reply.starts_with("HTTP/1.1 500"), "{reply}");
        }
    };
    faults(2000);
    let before = rss_kib(child.id());
    faults(4000);
    let grown = rss_kib(child.id()).saturating_sub(before);
    child.kill().unwrap();
    child.wait().unwrap();
    // The leak was ~4.6 MiB over 4000 requests; allocator noise stays under half of that.
    assert!(
        grown < 2048,
        "{grown} KiB gained over 4000 faulting requests"
    );
}

/// `stdout().flush()` writes the buffered output at once rather than at exit.
#[test]
fn native_stdout_flush_reaches_a_pipe_immediately() {
    use std::io::{BufRead, BufReader};
    use std::process::Stdio;
    use std::time::{Duration, Instant};

    let dir = scratch("native-flush");
    let source = write(
        &dir,
        "main.ms",
        "from \"@std/io.ms\" import stdout\nfrom \"@std/time.ms\" import sleep, duration\n\nexport def main() -> Int:\n    stdout().write(\"first\\n\").get()\n    stdout().flush().get()\n    sleep(duration(3000000000))\n    return 0\n",
    );
    let exe = dir.join("flush");
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["build", &source, "-o", exe.to_str().unwrap()]);
    assert_eq!(status, 0, "{err}");
    let started = Instant::now();
    let mut child = Command::new(&exe).stdout(Stdio::piped()).spawn().unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let took = started.elapsed();
    child.kill().unwrap();
    child.wait().unwrap();
    assert_eq!(line, "first\n");
    assert!(took < Duration::from_secs(2), "{took:?}");
}

/// The TLS stack's C objects survive the debug strip of the embedded archive: a program that
/// serves HTTP links. `llvm-strip --strip-debug` once corrupted `ring`'s objects for GNU ld.
#[test]
fn native_programs_using_tls_and_http_link() {
    let dir = scratch("native-link-net");
    let source = write(
        &dir,
        "main.ms",
        "from \"@std/http.ms\" import headers, HttpRequest, HttpResponse\nfrom \"@std/net.ms\" import network\n\ndef handle(request: HttpRequest) -> HttpResponse:\n    return HttpResponse(200, headers(), request.path.to_bytes())\n\nexport def main() -> Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle):\n        with let server = acquired:\n            return 0\n    return 1\n",
    );
    let exe = dir.join("net");
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["build", &source, "-o", exe.to_str().unwrap()]);
    assert_eq!((status, err.as_str()), (0, ""));
    assert_eq!(Command::new(&exe).status().unwrap().code(), Some(0));
}

/// SIGTERM used to cancel in-flight handlers at once (a 504) even when the server had a grace
/// period; the request now finishes and the program then exits 143.
#[test]
#[cfg(unix)]
fn native_sigterm_lets_in_flight_requests_finish_within_grace() {
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpStream;
    use std::os::unix::process::ExitStatusExt;
    use std::process::Stdio;
    use std::time::Duration;

    let dir = scratch("native-sigterm-grace");
    let source = write(
        &dir,
        "main.ms",
        "from \"@std/http.ms\" import headers, HttpRequest, HttpResponse, HttpServerOptions\nfrom \"@std/net.ms\" import network\nfrom \"@std/io.ms\" import stdout\nfrom \"@std/time.ms\" import sleep, duration\n\ndef handle(request: HttpRequest) -> HttpResponse:\n    sleep(duration(600000000))\n    return HttpResponse(200, headers(), \"done\".to_bytes())\n\nexport def main() -> Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle, options: HttpServerOptions(grace: duration(10000000000))):\n        with let server = acquired:\n            stdout().write(f\"{server.address()}\\n\").get()\n            stdout().flush().get()\n            let _ignored = server.wait()\n            return 0\n    return 1\n",
    );
    let exe = dir.join("server");
    let backend = Engine::new(Native);
    let (status, _, err) = ms(&backend, &["build", &source, "-o", exe.to_str().unwrap()]);
    assert_eq!(status, 0, "{err}");
    let mut child = Command::new(&exe).stdout(Stdio::piped()).spawn().unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let mut stream = TcpStream::connect(line.trim()).unwrap();
    write!(
        stream,
        "GET / HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n"
    )
    .unwrap();
    std::thread::sleep(Duration::from_millis(200));
    let killed = Command::new("kill")
        .args(["-TERM", &child.id().to_string()])
        .status()
        .unwrap();
    assert!(killed.success());
    let mut reply = String::new();
    stream.read_to_string(&mut reply).unwrap();
    let status = child.wait().unwrap();
    assert!(reply.starts_with("HTTP/1.1 200"), "{reply}");
    assert!(reply.ends_with("done"), "{reply}");
    assert_eq!(status.code(), Some(143), "{status:?} {:?}", status.signal());
}

/// The coordinator's signal cleanup must retain its control readers until every
/// member has drained; killing child processes immediately loses this response.
#[test]
#[cfg(unix)]
fn native_http_groups_drain_on_sigterm() {
    use std::io::{Read, Write};
    use std::net::TcpStream;
    use std::process::Stdio;
    use std::time::{Duration, Instant};

    for execution in ["workers(2)", "processes(2)"] {
        let dir = scratch(&format!("http-group-sigterm-{execution}"));
        let program = r#"
from "@std/http.ms" import Server, Router, Request, Response, HttpError, HttpServerOptions, serve, workers, processes, text_response
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import sleep
from "@std/io.ms" import stdout

def ready(server: Server) -> Unit:
    while not server.state.get().released: sleep(1.milliseconds)
    stdout().write(f"{server.address().get()}\n").get()
    stdout().flush().get()

def handle(request: Request) -> Response:
    stdout().write("handling\n").get()
    stdout().flush().get()
    sleep(600.milliseconds)
    return text_response("done")

def application(server: Server) -> Result[Unit, HttpError]:
    var routes = Router()
    routes.get("/", handle)
    with let tasks = TaskGroup[Unit]():
        if server.member_index == 0:
            let copy = server.clone()
            let _ready = tasks.spawn(lambda channel: ready(copy))
        return server.run(routes)

export def main() -> Int:
    serve("127.0.0.1:0", application, HttpServerOptions(grace: 5.seconds), EXECUTION).get()
    return 0
"#;
        let source = write(&dir, "main.ms", &program.replace("EXECUTION", execution));
        let exe = dir.join("server");
        let backend = Engine::new(Native);
        let (status, _, err) = ms(
            &backend,
            &[
                "build",
                &source,
                "-o",
                exe.to_str().unwrap(),
                "--build-type",
                "Debug",
            ],
        );
        assert_eq!(status, 0, "{execution}: {err}");
        let mut child = HttpChild(Command::new(&exe).stdout(Stdio::piped()).spawn().unwrap());
        let output = http_child_lines(&mut child.0);
        let address = output
            .recv_timeout(Duration::from_secs(10))
            .expect("HTTP group startup timed out");
        let mut stream = TcpStream::connect(address.trim()).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(10)))
            .unwrap();
        write!(
            stream,
            "GET / HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n"
        )
        .unwrap();
        let handling = output
            .recv_timeout(Duration::from_secs(10))
            .expect("HTTP handler did not start");
        assert_eq!(handling.trim(), "handling");
        assert!(
            Command::new("kill")
                .args(["-TERM", &child.0.id().to_string()])
                .status()
                .unwrap()
                .success()
        );
        let mut reply = String::new();
        stream.read_to_string(&mut reply).unwrap();
        let deadline = Instant::now() + Duration::from_secs(10);
        let status = loop {
            if let Some(status) = child.0.try_wait().unwrap() {
                break status;
            }
            if Instant::now() >= deadline {
                let _ = child.0.kill();
                let _ = child.0.wait();
                panic!("{execution}: coordinator did not finish shutdown");
            }
            std::thread::sleep(Duration::from_millis(10));
        };
        assert!(reply.starts_with("HTTP/1.1 200"), "{execution}: {reply}");
        assert!(reply.contains("done"), "{execution}: {reply}");
        assert_eq!(status.code(), Some(143), "{execution}: {status}");
    }
}

#[cfg(unix)]
struct HttpChild(std::process::Child);

#[cfg(unix)]
impl Drop for HttpChild {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[cfg(unix)]
fn http_child_lines(child: &mut std::process::Child) -> std::sync::mpsc::Receiver<String> {
    use std::io::BufRead;
    let stdout = child.stdout.take().unwrap();
    let (sender, receiver) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        for line in std::io::BufReader::new(stdout).lines() {
            let Ok(line) = line else {
                break;
            };
            if sender.send(line).is_err() {
                break;
            }
        }
    });
    receiver
}

#[cfg(unix)]
fn http_compile(source: &str, name: &str) -> std::path::PathBuf {
    http_compile_profile(source, name, "Debug")
}

#[cfg(unix)]
fn http_compile_profile(source: &str, name: &str, profile: &str) -> std::path::PathBuf {
    let dir = scratch(name);
    let source = write(&dir, "main.ms", source);
    let exe = dir.join("server");
    let (status, _, error) = ms(
        &Engine::new(Native),
        &[
            "build",
            &source,
            "-o",
            exe.to_str().unwrap(),
            "--build-type",
            profile,
        ],
    );
    assert_eq!(status, 0, "{error}");
    exe
}

#[test]
#[cfg(unix)]
fn native_http_process_startup_timeout_kills_stuck_initializers() {
    use std::process::Stdio;
    use std::time::{Duration, Instant};
    let exe = http_compile(
        r#"
from "@std/http.ms" import Server, Router, HttpError, HttpServerOptions, serve, processes
from "@std/process.ms" import control
from "@std/io.ms" import stdout

def application(server: Server) -> Result[Unit, HttpError]:
    stdout().write(f"{control().info().get().pid}\n").get()
    stdout().flush().get()
    if server.member_index == 0:
        var value = 0
        while True: value = (value + 1) % 1000000
    return server.run(Router())

export def main() -> Int:
    let result = serve("127.0.0.1:0", application, HttpServerOptions(grace: 0.seconds), processes(2, startup_timeout: 200.milliseconds, cleanup_timeout: 200.milliseconds))
    return 0 if result.is_error() else 1
"#,
        "http-process-stuck-startup",
    );
    let mut child = HttpChild(Command::new(exe).stdout(Stdio::piped()).spawn().unwrap());
    let lines = http_child_lines(&mut child.0);
    let mut members = Vec::new();
    for _ in 0..2 {
        members.push(
            lines
                .recv_timeout(Duration::from_secs(5))
                .expect("member startup did not publish PID")
                .parse::<u32>()
                .unwrap(),
        );
    }
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if let Some(status) = child.0.try_wait().unwrap() {
            assert!(status.success());
            break;
        }
        assert!(
            Instant::now() < deadline,
            "startup rollback did not terminate coordinator"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
    for pid in members {
        assert!(
            !Command::new("kill")
                .args(["-0", &pid.to_string()])
                .stderr(Stdio::null())
                .status()
                .unwrap()
                .success(),
            "member {pid} survived rollback"
        );
    }
}

#[test]
#[cfg(unix)]
fn native_http_process_members_stop_after_coordinator_loss() {
    use std::process::Stdio;
    use std::time::{Duration, Instant};
    let exe = http_compile(
        r#"
from "@std/http.ms" import Server, Router, HttpError, HttpServerOptions, serve, processes
from "@std/process.ms" import control
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import sleep

def ready(server: Server) -> Unit:
    while not server.is_ready(): sleep(1.milliseconds)
    stdout().write(f"{control().info().get().pid} {server.address().get()}\n").get()
    stdout().flush().get()

def application(server: Server) -> Result[Unit, HttpError]:
    with let tasks = TaskGroup[Unit]():
        let copy = server.clone()
        let task = tasks.spawn(lambda channel: ready(copy))
        return server.run(Router())

export def main() -> Int:
    serve("127.0.0.1:0", application, HttpServerOptions(grace: 0.seconds), processes(2, cleanup_timeout: 200.milliseconds)).get()
    return 0
"#,
        "http-process-parent-loss",
    );
    let mut child = HttpChild(Command::new(exe).stdout(Stdio::piped()).spawn().unwrap());
    let lines = http_child_lines(&mut child.0);
    let mut members = Vec::new();
    let mut address = String::new();
    for _ in 0..2 {
        let line = lines
            .recv_timeout(Duration::from_secs(10))
            .expect("member did not become ready");
        let (pid, bound) = line.split_once(' ').unwrap();
        members.push(pid.parse::<u32>().unwrap());
        address = bound.to_owned();
    }
    child.0.kill().unwrap();
    child.0.wait().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        let alive = members.iter().any(|pid| {
            let status = Command::new("ps")
                .args(["-o", "stat=", "-p", &pid.to_string()])
                .output()
                .unwrap();
            let state = String::from_utf8_lossy(&status.stdout);
            !state.trim().is_empty() && !state.trim().starts_with('Z')
        });
        if !alive {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "members survived coordinator loss: {members:?}"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
    let rebound =
        std::net::TcpListener::bind(&address).expect("members retained the listening socket");
    drop(rebound);
}

/// Measure the server heap from a separate process: client/test-runner allocations
/// must not be mistaken for callback retention. This covers compiler-owned callee
/// pins as well as with-owned request, route and middleware state.
#[test]
#[cfg(unix)]
fn native_http_callback_ownership_recovers_after_deadlines_and_faults() {
    http_callback_ownership("Debug");
}

#[test]
#[cfg(unix)]
fn native_release_http_callback_ownership_recovers_after_deadlines_and_faults() {
    http_callback_ownership("Release");
}

#[cfg(unix)]
fn http_callback_ownership(profile: &str) {
    use std::io::{Read, Write};
    use std::net::TcpStream;
    use std::process::Stdio;
    use std::time::Duration;

    let source = r#"from "@std/http.ms" import Server, Router, HttpError, HttpServerOptions, text_response, stream_response
from "@std/web_compression.ms" import compression, Compression
from "@std/web_multipart.ms" import multipart
from "@std/web_build.ms" import StaticBuild
from "@std/web.ms" import html, cors, Cors
from "@std/web_cache.ms" import ResponseCache
from "@std/web_html.ms" import Html, HtmlLimits, html_stream
from "@std/web_assets.ms" import asset, asset_response
from "@std/tasks.ms" import TaskGroup
from "@std/time.ms" import sleep
from "@std/process.ms" import control
from "@std/io.ms" import stdout, WriteStream, read_all
from "@std/core.ms" import Closeable, panic
from "@std/bytes.ms" import Bytes

type Payload:
    bytes: Bytes
impl Closeable for Payload:
    var def close() -> Unit: ()

export def main() -> Int:
    let server = Server("127.0.0.1:0", HttpServerOptions(timeout: 500.milliseconds))
    with let tasks = TaskGroup[Result[Unit, HttpError]]():
        let owner = server.clone()
        let running = tasks.spawn(lambda channel:
            var routes = Router()
            routes.use(lambda request, next: next(request))
            routes.use(cors(Cors(origins: ["https://example.test"])).get().call)
            routes.use(compression(Compression(min_bytes: 0)).get().call)
            routes.get("/gzip", lambda request: stream_response(lambda (var output: WriteStream):
                try output.write("first fragment")
                try output.flush()
                sleep(5.seconds)
                return ok(())
            ))
            routes.post("/upload", lambda request:
                multipart(request, lambda part:
                    sleep(5.seconds)
                    return ok(())
                ).get()
                return text_response("done")
            )
            routes.post("/upload-read", lambda request:
                multipart(request, lambda part: read_all(part.body, 4096).map(lambda bytes: ())).get()
                return text_response("done")
            )
            var site = StaticBuild()
            site.render("/", "index.html", lambda request: html("<h1>Generated</h1>")).get()
            routes.get("/stage", lambda request:
                site.stage(lambda path:
                    sleep(5.seconds)
                    return ok(())
                ).get()
                return text_response("done")
            )
            let cache = ResponseCache()
            routes.get("/cache", lambda request: cache.handle(request, lambda incoming:
                sleep(5.seconds)
                return text_response("done")
            ))
            var fragments = List[Html]()
            for index in 0..8: fragments.append(Html.Trusted("h".repeat(524288).get().clone()))
            routes.get("/html", lambda request: html_stream(fragments.clone(), limits: HtmlLimits(max_bytes: 8388608)))
            let file = asset("a".repeat(4194304).get().to_bytes()).get().clone()
            routes.get("/ranges", lambda request: asset_response(request, file))
            routes.get("/slow", lambda request:
                with let payload = Payload("x".repeat(512).get().to_bytes()):
                    sleep(5.seconds)
                    return text_response("late")
            )
            routes.get("/fault", lambda request:
                with let payload = Payload("x".repeat(512).get().to_bytes()):
                    panic("expected fault")
                    return text_response("unreachable")
            )
            routes.get("/heap", lambda request: text_response(f"{control().memory_usage().get().heap_used}"))
            return owner.run(routes)
        )
        while server.address().is_none(): sleep(1.milliseconds)
        stdout().write(f"{server.address().get()}\n").get()
        stdout().flush().get()
        running.result().get().get()
    return 0
"#;
    let exe = http_compile_profile(
        source,
        &format!("native-http-callback-ownership-{profile}"),
        profile,
    );
    let mut child = HttpChild(
        Command::new(exe)
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .unwrap(),
    );
    let lines = http_child_lines(&mut child.0);
    let address = lines.recv_timeout(Duration::from_secs(10)).unwrap();
    let request = |path: &str| {
        let mut stream = TcpStream::connect(&address).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        if path.starts_with("/upload") {
            write!(stream, "POST {path} HTTP/1.1\r\nHost: test\r\nContent-Type: multipart/form-data; boundary=x\r\nContent-Length: 4096\r\nConnection: close\r\n\r\n--x\r\nContent-Disposition: form-data; name=file\r\n\r\na").unwrap();
        } else {
            let encoding = if path == "/gzip" {
                "Accept-Encoding: gzip\r\n"
            } else if path == "/ranges" {
                "Range: bytes=0-2097151,2097152-4194303\r\n"
            } else {
                ""
            };
            write!(
                stream,
                "GET {path} HTTP/1.1\r\nHost: test\r\nOrigin: https://example.test\r\n{encoding}Connection: close\r\n\r\n"
            )
            .unwrap();
        }
        let mut reply = Vec::new();
        if path == "/html" || path == "/ranges" {
            // Prove the producer reached the transport before withholding body
            // reads. Do not use buffered read-ahead, which could drain the body.
            while !reply.ends_with(b"\r\n\r\n") {
                assert!(reply.len() < 65536, "oversized response head");
                let mut byte = [0];
                stream
                    .read_exact(&mut byte)
                    .expect("complete response head");
                reply.push(byte[0]);
            }
            if reply.starts_with(b"HTTP/1.1 200") || reply.starts_with(b"HTTP/1.1 206") {
                let head_end = reply.len();
                while reply.len() == head_end || !reply.ends_with(b"\r\n") {
                    assert!(reply.len() - head_end < 128, "oversized chunk size");
                    let mut byte = [0];
                    stream.read_exact(&mut byte).expect("first chunk size");
                    reply.push(byte[0]);
                }
                let size = std::str::from_utf8(&reply[head_end..reply.len() - 2]).unwrap();
                assert!(usize::from_str_radix(size, 16).unwrap() > 0);
                let mut byte = [0];
                stream.read_exact(&mut byte).expect("first producer byte");
                reply.push(byte[0]);
                std::thread::sleep(Duration::from_millis(750));
            }
        }
        stream.read_to_end(&mut reply).unwrap();
        String::from_utf8_lossy(&reply).into_owned()
    };
    let heap = || -> usize {
        // A sampling request has the same finite deadline. Retry an expired
        // sample under competing compiler load; exercised callback statuses above
        // remain strict, and invalid heap responses still fail this test.
        for _ in 0..5 {
            let reply = request("/heap");
            if reply.starts_with("HTTP/1.1 200") {
                return reply
                    .split_once("\r\n\r\n")
                    .unwrap()
                    .1
                    .trim()
                    .parse()
                    .unwrap();
            }
            assert!(
                reply.is_empty() || reply.starts_with("HTTP/1.1 504"),
                "heap: {reply}"
            );
            std::thread::sleep(Duration::from_millis(100));
        }
        panic!("heap sampling never recovered");
    };
    let mut samples = Vec::new();
    #[cfg(target_os = "linux")]
    let mut resident_samples = Vec::new();
    #[cfg(target_os = "linux")]
    let mut descriptor_samples = Vec::new();
    for cycle in 0..4 {
        for (path, status) in [
            ("/slow", 504),
            ("/fault", 500),
            ("/gzip", 200),
            ("/upload", 504),
            ("/upload-read", 504),
            ("/stage", 504),
            ("/cache", 504),
            ("/html", 200),
            ("/ranges", 206),
        ] {
            for _ in 0..4 {
                let mut reply = request(path);
                if path == "/html" || path == "/ranges" {
                    for retry in 0..4 {
                        if !reply.starts_with("HTTP/1.1 504 ") {
                            break;
                        }
                        // A fully framed precommit deadline is not an exercised
                        // blocked producer. Count no success, but retain its
                        // allocations in the subsequent recovery measurements.
                        let (head, body) = reply.split_once("\r\n\r\n").unwrap();
                        let length = head
                            .lines()
                            .find_map(|line| {
                                line.strip_prefix("Content-Length: ")
                                    .map(|value| value.parse::<usize>().unwrap())
                            })
                            .expect("framed precommit timeout");
                        assert_eq!(body.len(), length, "{reply}");
                        eprintln!("{profile} cycle {cycle} {path} precommit timeout retry {retry}");
                        reply = request(path);
                    }
                }
                assert!(
                    reply.starts_with(&format!("HTTP/1.1 {status}")),
                    "{path}: {reply}"
                );
                if path == "/html" || path == "/ranges" {
                    assert!(
                        reply
                            .to_ascii_lowercase()
                            .contains("transfer-encoding: chunked")
                    );
                    assert!(
                        !reply.ends_with("0\r\n\r\n"),
                        "{path} completed instead of exercising blocked-write cancellation"
                    );
                }
            }
            eprintln!("{profile} cycle {cycle} {path} heap {}", heap());
        }
        let measured_heap = heap();
        if cycle == 0 {
            continue;
        } // Warm protocol and diagnostic allocation paths first.
        #[cfg(target_os = "linux")]
        {
            let base = std::path::PathBuf::from(format!("/proc/{}", child.0.id()));
            let status = std::fs::read_to_string(base.join("status")).unwrap();
            let rss: usize = status
                .lines()
                .find(|line| line.starts_with("VmRSS:"))
                .unwrap()
                .split_whitespace()
                .nth(1)
                .unwrap()
                .parse()
                .unwrap();
            resident_samples.push(rss);
            // EOF can reach the client between shutdown(2) and close(2).
            // Observe the idle floor over two scheduler periods, not that race.
            let mut descriptors = usize::MAX;
            for _ in 0..10 {
                std::thread::sleep(Duration::from_millis(20));
                descriptors = descriptors.min(std::fs::read_dir(base.join("fd")).unwrap().count());
            }
            descriptor_samples.push(descriptors);
        }
        samples.push(measured_heap);
    }
    // Runtime housekeeping may overlap the sampled request. A small fixed
    // allowance tolerates that; the old callee leak grew hundreds per callback.
    assert!(
        samples.iter().max().unwrap() - samples.iter().min().unwrap() <= 256,
        "heap retained after callbacks: {samples:?}"
    );
    #[cfg(target_os = "linux")]
    {
        assert!(
            resident_samples.iter().max().unwrap() - resident_samples.iter().min().unwrap() <= 4096,
            "resident memory did not recover: {resident_samples:?} KiB"
        );
        assert!(
            descriptor_samples
                .iter()
                .all(|count| *count == descriptor_samples[0]),
            "descriptors retained after callbacks: {descriptor_samples:?}"
        );
    }
}
