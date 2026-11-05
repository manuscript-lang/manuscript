//! Complete public teaching examples run with their documented fixtures and output.

use ms_json::Json;
use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const MARKER: &str = "<!-- manuscript-example: ";

struct Example {
    file: PathBuf,
    line: usize,
    spec: Json,
    source: String,
}

fn source_files(dir: &Path, extension: &str, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            source_files(&path, extension, out);
        } else if path.extension().is_some_and(|e| e == extension) {
            out.push(path);
        }
    }
}

fn examples() -> Vec<Example> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut files = Vec::new();
    source_files(&root.join("documentation"), "md", &mut files);
    files.sort();
    let mut found = Vec::new();
    for file in files {
        let text = fs::read_to_string(&file).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        for (i, line) in lines.iter().enumerate() {
            assert!(
                !line.trim_start().starts_with("```manuscript")
                    || line.starts_with("```manuscript"),
                "{file:?}:{}: keep teaching fences unindented for discovery",
                i + 1
            );
            if line.starts_with("```manuscript") && !line.contains("schema=true") {
                assert!(
                    i > 0 && lines[i - 1].starts_with(MARKER),
                    "{file:?}:{}: teaching fence needs a runnable expectation",
                    i + 1
                );
            }
            let Some(rest) = line.strip_prefix(MARKER) else {
                continue;
            };
            let mut spec = ms_json::parse(rest.trim_end().trim_end_matches("-->").trim())
                .unwrap_or_else(|err| panic!("{file:?}:{}: {err}", i + 1));
            let fence = lines.get(i + 1).copied().unwrap_or("");
            assert!(fence.starts_with("```manuscript"), "{file:?}:{}", i + 1);
            if let Some((_, tail)) = fence.split_once("filename=\"") {
                let filename = tail.split('"').next().unwrap();
                if let Some(given) = string(&spec, "filename") {
                    assert_eq!(given, filename, "{file:?}:{}: conflicting filenames", i + 1);
                } else {
                    spec.set("filename", Json::from(filename));
                }
            }
            let body: Vec<&str> = lines[i + 2..]
                .iter()
                .copied()
                .take_while(|l| !l.starts_with("```"))
                .collect();
            let source = body.join("\n") + "\n";
            assert!(
                !source.contains('\t'),
                "{file:?}:{}: tabs in example",
                i + 1
            );
            assert!(
                !source.contains(".get()"),
                "{file:?}:{}: unwrap-style call",
                i + 1
            );
            assert!(
                source.contains("export fn main() Int:")
                    || source.lines().any(|l| l.starts_with("test ")),
                "{file:?}:{}: example needs main or test",
                i + 1
            );
            found.push(Example {
                file: file.clone(),
                line: i + 1,
                spec,
                source,
            });
        }
    }
    found
}

fn string<'a>(spec: &'a Json, key: &str) -> Option<&'a str> {
    spec.get(key).and_then(Json::as_str)
}

fn safe_path(root: &Path, name: &str) -> PathBuf {
    let relative = Path::new(name);
    assert!(
        !relative.as_os_str().is_empty()
            && relative
                .components()
                .all(|c| matches!(c, Component::Normal(_))),
        "unsafe fixture path: {name}"
    );
    root.join(relative)
}

fn write_file(root: &Path, name: &str, contents: &str) {
    let path = safe_path(root, name);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, contents).unwrap();
}

struct HttpFixture {
    url: String,
    stop: Arc<AtomicBool>,
    thread: Option<thread::JoinHandle<()>>,
}

impl HttpFixture {
    fn new(spec: &Json) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/", listener.local_addr().unwrap());
        listener.set_nonblocking(true).unwrap();
        let stop = Arc::new(AtomicBool::new(false));
        let done = stop.clone();
        let status = spec.get("status").and_then(Json::as_i64).unwrap_or(200);
        let body = string(spec, "body").unwrap_or("").to_string();
        let response = format!(
            "HTTP/1.1 {status} Fixture\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        let thread = thread::spawn(move || {
            while !done.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((mut stream, _)) => {
                        stream
                            .set_read_timeout(Some(Duration::from_secs(2)))
                            .unwrap();
                        let mut request = [0; 8192];
                        let _ = stream.read(&mut request);
                        let _ = stream.write_all(response.as_bytes());
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(10))
                    }
                    Err(e) => panic!("HTTP fixture: {e}"),
                }
            }
        });
        Self {
            url,
            stop,
            thread: Some(thread),
        }
    }
}

impl Drop for HttpFixture {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        self.thread.take().unwrap().join().unwrap();
    }
}

fn ms(dir: &Path, args: &[&str], stdin: &str) -> (i32, String, String) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_ms"))
        .current_dir(dir)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(stdin.as_bytes()).ok();
    let out = child.wait_with_output().unwrap();
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

#[test]
fn marked_tutorial_examples_compile_and_pass() {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!("ms-doc-examples-{}-{nonce}", std::process::id()));
    fs::create_dir_all(&root).unwrap();
    let mut failures = Vec::new();
    let all = examples();
    assert!(all.len() >= 73, "found only {} examples", all.len());
    for (n, example) in all.iter().enumerate() {
        let name = format!("{}:{}", example.file.display(), example.line);
        let mut cases = vec![&example.spec];
        if let Some(extra) = example.spec.get("cases").and_then(Json::as_array) {
            cases.extend(extra);
        }
        for (case_n, case) in cases.into_iter().enumerate() {
            let dir = root.join(format!("{n}-{case_n}"));
            fs::create_dir_all(&dir).unwrap();
            let filename = string(&example.spec, "filename").unwrap_or("example.ms");
            write_file(&dir, filename, &example.source);
            // Additional cases are independent invocations, not inherited inputs.
            if let Some(Json::Obj(files)) = case.get("files") {
                for (path, contents) in files {
                    assert_ne!(
                        safe_path(&dir, path),
                        safe_path(&dir, filename),
                        "{name}: fixture overwrites displayed source"
                    );
                    write_file(
                        &dir,
                        path,
                        contents.as_str().expect("fixture contents must be text"),
                    );
                }
            }
            let http = case.get("http").map(HttpFixture::new);
            let given: Vec<String> = case
                .get("args")
                .and_then(Json::as_array)
                .unwrap_or(&[])
                .iter()
                .map(|arg| {
                    let arg = arg.as_str().expect("argument must be text");
                    if let Some(server) = &http {
                        arg.replace("$HTTP_URL", &server.url)
                    } else {
                        arg.to_string()
                    }
                })
                .collect();
            let mode = string(&example.spec, "mode").unwrap_or("run");
            assert!(
                matches!(mode, "run" | "test" | "bench"),
                "{name}: unsupported execution mode {mode}"
            );
            let target = string(&example.spec, "target").unwrap_or(filename);
            safe_path(&dir, target);
            let mut args = vec![mode, target];
            if mode == "bench" {
                let (code, stdout, stderr) = ms(&dir, &["test", target], "");
                if code != 0
                    || !stderr.is_empty()
                    || string(case, "test_stdout")
                        .expect("benchmark needs its correctness-test output")
                        != stdout
                {
                    failures.push(format!(
                        "{name}: benchmark correctness test failed: {stdout:?} {stderr:?}"
                    ));
                }
                args.extend(["--time", "5ms", "--samples", "2"]);
            }
            if mode == "run" {
                args.push("--");
                args.extend(given.iter().map(String::as_str));
            }
            let (code, stdout, stderr) = ms(&dir, &args, string(case, "stdin").unwrap_or(""));
            let want_code = case.get("exit_code").and_then(Json::as_i64).unwrap_or(0) as i32;
            let want_stdout = string(case, "stdout").or_else(|| (mode == "run").then_some(""));
            let want_stderr = string(case, "stderr").unwrap_or("");
            if code != want_code
                || want_stdout.is_some_and(|s| s != stdout)
                || want_stderr != stderr
            {
                failures.push(format!("{name} case {case_n}: expected exit {want_code}, stdout {want_stdout:?}, stderr {want_stderr:?}; got exit {code}, stdout {stdout:?}, stderr {stderr:?}"));
            }
            if let Some(Json::Obj(files)) = case.get("want_files") {
                for (path, want) in files {
                    let want = want.as_str().expect("expected file contents must be text");
                    let got = fs::read_to_string(safe_path(&dir, path));
                    if got.as_deref().ok() != Some(want) {
                        failures.push(format!(
                            "{name} case {case_n}: file {path}: expected {want:?}, got {got:?}"
                        ));
                    }
                }
            }
        }
    }
    fs::remove_dir_all(&root).ok();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
