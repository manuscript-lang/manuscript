//! The Rust engine end to end: load, check, an injected lowering, Cranelift,
//! link, run. Lowering from the typed HIR is a separate workstream, so the
//! tests supply the MIR the lowering would produce.

use std::path::{Path, PathBuf};
use std::process::Command;

use ms_cli::backend::Io;
use ms_cli::engine::RustBackend;
use ms_driver::{Lower, LowerOptions, Module, Native};

/// A lowering that ignores the program and returns fixed MIR.
struct Fixed(&'static str);

impl Lower for Fixed {
    fn lower(&self, _: &ms_check::Program, _: &str, _: &LowerOptions) -> Result<Module, String> {
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

fn ms<L: Lower>(backend: &RustBackend<L>, args: &[&str]) -> (i32, String, String) {
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

const MAIN: &str = "export fn main() Int:\n    return 0\n";

#[test]
fn run_returns_the_program_status() {
    let dir = scratch("run");
    let source = write(&dir, "main.ms", MAIN);
    let backend = RustBackend::new(Fixed(EXIT_SEVEN));
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!((status, err.as_str()), (7, ""));
}

#[test]
fn build_writes_an_executable_and_reports_it() {
    let dir = scratch("build");
    let source = write(&dir, "main.ms", MAIN);
    let out = dir.join("prog");
    let backend = RustBackend::new(Fixed(EXIT_SEVEN));
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
    let source = write(&dir, "main.ms", "export fn main() Int:\n    return \"x\"\n");
    let backend = RustBackend::new(Fixed(EXIT_SEVEN));
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
    let backend = RustBackend::new(Fixed(EXIT_SEVEN));
    for (text, expected) in [
        ("fn main() Int:\n    return 0\n", "main is not exported"),
        (
            "export fn other() Int:\n    return 0\n",
            "no main function is declared",
        ),
        (
            "export fn main(x: Int) Int:\n    return x\n",
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
    write(&dir, "lib.ms", "export fn one() Int:\n    return 1\n");
    let source = write(
        &dir,
        "main.ms",
        "import { one } from \"./lib.ms\"\n\nexport fn main() Int:\n    return one()\n",
    );
    let backend = RustBackend::new(Fixed(EXIT_SEVEN));
    assert_eq!(ms(&backend, &["run", &source]).0, 7);

    let missing = write(
        &dir,
        "main.ms",
        "import { one } from \"./nope.ms\"\n\nexport fn main() Int:\n    return 0\n",
    );
    let (status, _, err) = ms(&backend, &["run", &missing]);
    assert_eq!(status, 1);
    assert!(err.contains("cannot find module ./nope.ms"), "{err}");
}

#[test]
fn unavailable_lowering_is_a_lowering_diagnostic() {
    let dir = scratch("unavailable");
    let source = write(&dir, "main.ms", MAIN);
    let backend = RustBackend::new(ms_driver::Unavailable);
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
    let backend = RustBackend::new(Fixed(EXIT_SEVEN));
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
        "export fn one() Int:\n    return 1\n",
    );
    let backend = RustBackend::new(Fixed(EXIT_SEVEN));
    let manifest = dir.join("ms.toml");
    let (status, _, err) = ms(&backend, &["build", manifest.to_str().unwrap()]);
    assert_eq!(status, 1);
    assert!(
        err.contains("library project has no executable entry"),
        "{err}"
    );
}

const TESTS: &str = "import {expect_equal} from \"@std/testing.ms\"\n\ntest \"adds\":\n    try expect_equal(1 + 1, 2)\n\ntest \"fails\":\n    try expect_equal(1 + 1, 3)\n\ntest \"passes too\":\n    try expect_equal(2 * 2, 4)\n";

#[test]
fn native_lowering_runs_real_programs() {
    let dir = scratch("native-run");
    let source = write(
        &dir,
        "main.ms",
        "export fn main() Int:\n    return 6 * 7 - 40\n",
    );
    let backend = RustBackend::new(Native);
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
        "import {parse, format} from \"@std/semver.ms\"\n\nexport fn main() Int:\n    let v = parse(\"1.2.3\").get()\n    if format(v) == \"1.2.3\":\n        return 0\n    return 1\n",
    );
    let backend = RustBackend::new(Native);
    let (status, _, err) = ms(&backend, &["run", &source]);
    assert_eq!((status, err.as_str()), (0, ""));
}

#[test]
fn native_tests_run_one_process_each() {
    let dir = scratch("native-test");
    let source = write(&dir, "sample_test.ms", TESTS);
    let backend = RustBackend::new(Native);
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
    let backend = RustBackend::new(Native);
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
    let backend = RustBackend::new(Native);
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
    let backend = RustBackend::new(Native);
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
        "type Link:\n    case End\n    case More(next: Link)\n    case Tag(n: Int, rest: Link)\n\nfn build(n: Int) Link:\n    if n == 0:\n        return End\n    if n % 2 == 0:\n        return More(build(n - 1))\n    return Tag(n, build(n - 1))\n\nfn sum(l: Link, acc: Int) Int:\n    match l:\n        End:\n            return acc\n        More(r):\n            return sum(r, acc)\n        Tag(n, r):\n            return sum(r, acc + n)\n\nexport fn main() Int:\n    let a = build(100000)\n    let b = a\n    if sum(a, 0) != 2500000000:\n        return 1\n    if sum(b, 0) != 2500000000:\n        return 2\n    return 0\n",
    );
    let backend = RustBackend::new(Native);
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
        "type Cell:\n    n: Int\n    tag: String\n\nexport fn main() Int:\n    var cells = [Cell(n: 1, tag: \"a\"), Cell(n: 2, tag: \"b\")]\n    let before = cells\n    cells[1].n = 9\n    cells[0].tag = \"z\"\n    var grid = [[1], [2]]\n    grid[1].append(3)\n    if cells[1].n != 9 or cells[0].tag != \"z\":\n        return 1\n    if before[1].n != 2 or before[0].tag != \"a\":\n        return 2\n    if grid[1].length() != 2:\n        return 3\n    return 0\n",
    );
    let backend = RustBackend::new(Native);
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
        "export fn main() Int:\n    var items = [1, 2, 3]\n    items.set(value: 8, 0)\n    items.insert(value: 5, 1)\n    if items[0] != 8 or items[1] != 5 or items.length() != 4:\n        return 1\n    return 0\n",
    );
    let backend = RustBackend::new(Native);
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
        "import {parse, JsonValue, JsonError} from \"@std/json.ms\"\n\nexport fn main() Int:\n    let n = 50000\n    let text = \"{\"[\".repeat(n).get()}1{\"]\".repeat(n).get()}\"\n    let r: Result[JsonValue, JsonError] = parse(text)\n    if r.is_error():\n        return 1\n    return 0\n",
    );
    let backend = RustBackend::new(Native);
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
        "import {headers, HttpRequest, HttpResponse} from \"@std/http.ms\"\nimport network from \"@std/net.ms\"\nimport {stdout} from \"@std/io.ms\"\nimport {sleep, duration} from \"@std/time.ms\"\n\nfn handle(request: HttpRequest) HttpResponse:\n    if request.path == \"/slow\":\n        sleep(duration(500000000))\n    return HttpResponse(200, headers(), request.path.to_bytes())\n\nexport fn main() Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle):\n        with server = acquired:\n            stdout().write(\"{server.address()}\\n\").get()\n            stdout().flush().get()\n            let _ignored = server.wait()\n            return 0\n    return 1\n",
    );
    let exe = dir.join("server");
    let backend = RustBackend::new(Native);
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
        "import {headers, HttpRequest, HttpResponse} from \"@std/http.ms\"\nimport network from \"@std/net.ms\"\nimport {stdout} from \"@std/io.ms\"\nimport {commands} from \"@std/process.ms\"\n\nfn handle(request: HttpRequest) HttpResponse:\n    if request.path == \"/slow\":\n        let _out = commands().run(\"sleep\", [\"0.5\"])\n    return HttpResponse(200, headers(), request.path.to_bytes())\n\nexport fn main() Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle):\n        with server = acquired:\n            stdout().write(\"{server.address()}\\n\").get()\n            stdout().flush().get()\n            let _ignored = server.wait()\n            return 0\n    return 1\n",
    );
    let exe = dir.join("server");
    let backend = RustBackend::new(Native);
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
        "import {headers, HttpRequest, HttpResponse} from \"@std/http.ms\"\nimport network from \"@std/net.ms\"\nimport {stdout} from \"@std/io.ms\"\n\nfn handle(request: HttpRequest) HttpResponse:\n    let xs: List[Int] = []\n    let i = request.path.length()\n    return HttpResponse(200, headers(), \"{xs[i]}\".to_bytes())\n\nexport fn main() Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle):\n        with server = acquired:\n            stdout().write(\"{server.address()}\\n\").get()\n            stdout().flush().get()\n            let _ignored = server.wait()\n            return 0\n    return 1\n",
    );
    let exe = dir.join("server");
    let backend = RustBackend::new(Native);
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
        "import stdout from \"@std/io.ms\"\nimport {sleep, duration} from \"@std/time.ms\"\n\nexport fn main() Int:\n    stdout().write(\"first\\n\").get()\n    stdout().flush().get()\n    sleep(duration(3000000000))\n    return 0\n",
    );
    let exe = dir.join("flush");
    let backend = RustBackend::new(Native);
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
        "import {headers, HttpRequest, HttpResponse} from \"@std/http.ms\"\nimport network from \"@std/net.ms\"\n\nfn handle(request: HttpRequest) HttpResponse:\n    return HttpResponse(200, headers(), request.path.to_bytes())\n\nexport fn main() Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle):\n        with server = acquired:\n            return 0\n    return 1\n",
    );
    let exe = dir.join("net");
    let backend = RustBackend::new(Native);
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
        "import {headers, HttpRequest, HttpResponse} from \"@std/http.ms\"\nimport network from \"@std/net.ms\"\nimport {stdout} from \"@std/io.ms\"\nimport {sleep, duration} from \"@std/time.ms\"\n\nfn handle(request: HttpRequest) HttpResponse:\n    sleep(duration(600000000))\n    return HttpResponse(200, headers(), \"done\".to_bytes())\n\nexport fn main() Int:\n    if let acquired = network().serve(address: \"127.0.0.1:0\", handler: handle, grace: duration(10000000000)):\n        with server = acquired:\n            stdout().write(\"{server.address()}\\n\").get()\n            stdout().flush().get()\n            let _ignored = server.wait()\n            return 0\n    return 1\n",
    );
    let exe = dir.join("server");
    let backend = RustBackend::new(Native);
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
