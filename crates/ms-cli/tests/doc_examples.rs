//! Tutorial fences marked `manuscript-example` must still compile and pass.
//!
//! `test` examples run under `ms test`. `run` examples are type-checked, and
//! also executed with their `args`, `stdin` and `stdout` when they need
//! neither files nor an HTTP server.

use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use ms_json::Json;

const MARKER: &str = "<!-- manuscript-example: ";

struct Example {
    file: PathBuf,
    line: usize,
    spec: String,
    source: String,
}

fn source_files(dir: &Path, ext: &str, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            source_files(&path, ext, out);
        } else if path.extension().is_some_and(|e| e == ext) {
            out.push(path);
        }
    }
}

/// The text of a comment line with its `//` prefix removed; other lines pass through.
fn uncomment(line: &str) -> &str {
    let trimmed = line.trim_start();
    match trimmed.strip_prefix("//") {
        Some(rest) => rest.strip_prefix(' ').unwrap_or(rest),
        None => line,
    }
}

/// Marked fences of `files`, read as Markdown (`documentation/`) or as the
/// comment blocks of `.ms` sources (`stdlib/`). With `all_fences`, a
/// `manuscript` fence without a marker is reported with an empty spec.
fn examples_in(files: &[PathBuf], all_fences: bool) -> Vec<Example> {
    let mut found = Vec::new();
    for file in files {
        let text = fs::read_to_string(file).unwrap();
        let comments = file.extension().is_some_and(|e| e == "ms");
        let lines: Vec<&str> = text
            .lines()
            .map(|l| if comments { uncomment(l) } else { l })
            .collect();
        for (i, line) in lines.iter().enumerate() {
            let marked = line.strip_prefix(MARKER);
            let fence_at = if marked.is_some() { i + 1 } else { i };
            let fence = lines.get(fence_at).copied().unwrap_or("");
            let is_fence = fence.starts_with("```manuscript");
            if marked.is_none() && !(all_fences && is_fence && !prev_is_marker(&lines, i)) {
                continue;
            }
            assert!(is_fence, "{file:?}:{}", i + 1);
            let spec = marked
                .map(|rest| rest.trim_end().trim_end_matches("-->").trim().to_string())
                .unwrap_or_default();
            let body: Vec<&str> = lines[fence_at + 1..]
                .iter()
                .copied()
                .take_while(|l| !l.starts_with("```"))
                .collect();
            found.push(Example {
                file: file.clone(),
                line: i + 1,
                spec,
                source: body.join("\n") + "\n",
            });
        }
    }
    found
}

fn prev_is_marker(lines: &[&str], i: usize) -> bool {
    i > 0 && lines[i - 1].starts_with(MARKER)
}

fn repo_files(dir: &str, ext: &str) -> Vec<PathBuf> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join(dir);
    let mut files = Vec::new();
    source_files(&root, ext, &mut files);
    files.sort();
    files
}

fn examples() -> Vec<Example> {
    examples_in(&repo_files("documentation", "md"), false)
}

fn ms(args: &[&str], stdin: &str, cwd: Option<&Path>) -> (Option<i32>, String, String) {
    let mut command = Command::new(env!("CARGO_BIN_EXE_ms"));
    command
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    let mut child = command.spawn().unwrap();
    child.stdin.take().unwrap().write_all(stdin.as_bytes()).ok();
    let out = child.wait_with_output().unwrap();
    (
        out.status.code(),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

/// Serves `body` with `status` to every request until the process exits.
fn serve_http(status: i64, body: String) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/", listener.local_addr().unwrap());
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut buf = [0u8; 4096];
            let _ = stream.read(&mut buf);
            let reply = format!(
                "HTTP/1.1 {status} X\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(reply.as_bytes());
        }
    });
    url
}

fn json_strings(value: Option<&Json>) -> Vec<String> {
    let items = value.and_then(Json::as_array).unwrap_or_default();
    items
        .iter()
        .filter_map(|v| v.as_str().map(str::to_string))
        .collect()
}

fn json_files(value: Option<&Json>) -> Vec<(String, String)> {
    match value {
        Some(Json::Obj(fields)) => fields
            .iter()
            .map(|(k, v)| (k.clone(), v.as_str().unwrap_or_default().to_string()))
            .collect(),
        _ => Vec::new(),
    }
}

/// Runs one case of a `run` example in a fresh directory and returns what differs.
/// A case states its own `args`, `stdin`, `files`, `http`, `stdout`, `exit_code`
/// and `want_files`; `stdout` and `want_files` are checked only when present.
fn run_case(path: &str, dir: &Path, case: &Json) -> Option<String> {
    fs::create_dir_all(dir).unwrap();
    for (name, text) in json_files(case.get("files")) {
        fs::write(dir.join(name), text).unwrap();
    }
    let url = case.get("http").map(|http| {
        let status = http.get("status").and_then(Json::as_i64).unwrap_or(200);
        let body = http.get("body").and_then(Json::as_str).unwrap_or_default();
        serve_http(status, body.to_string())
    });
    let args: Vec<String> = json_strings(case.get("args"))
        .into_iter()
        .map(|a| a.replace("$HTTP_URL", url.as_deref().unwrap_or("")))
        .collect();
    let mut argv = vec!["run", path, "--"];
    argv.extend(args.iter().map(String::as_str));
    let stdin = case.get("stdin").and_then(Json::as_str).unwrap_or_default();
    let (code, got, err) = ms(&argv, stdin, Some(dir));
    let want_code = case.get("exit_code").and_then(Json::as_i64).unwrap_or(0);
    let mut problems = Vec::new();
    if code != Some(want_code as i32) {
        problems.push(format!("exit code {code:?}, want {want_code}"));
    }
    if let Some(want) = case.get("stdout").and_then(Json::as_str)
        && got != want
    {
        problems.push(format!("stdout {got:?}, want {want:?}"));
    }
    for (name, want) in json_files(case.get("want_files")) {
        let have = fs::read_to_string(dir.join(&name)).unwrap_or_default();
        if have != want {
            problems.push(format!("file {name}: {have:?}, want {want:?}"));
        }
    }
    (!problems.is_empty()).then(|| format!("args {args:?}: {}\n{err}", problems.join("; ")))
}

fn verify(examples: &[Example], label: &str) {
    let dir = std::env::temp_dir().join(format!("ms-{label}-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let mut failures = Vec::new();
    for (n, example) in examples.iter().enumerate() {
        let path = dir.join(format!("example{n}.ms"));
        fs::write(&path, &example.source).unwrap();
        let path = path.to_str().unwrap();
        let name = format!("{}:{}", example.file.display(), example.line);
        if example.spec.contains("\"mode\":\"fragment\"") {
            continue;
        }
        if example.spec.contains("\"mode\":\"test\"") {
            let (code, _, err) = ms(&["test", path], "", None);
            if code != Some(0) {
                failures.push(format!("{name}: ms test failed\n{err}"));
            }
            continue;
        }
        if example.spec.contains("\"mode\":\"bench\"") {
            let (code, _, err) = ms(
                &["bench", path, "--time", "5ms", "--samples", "2"],
                "",
                None,
            );
            if code != Some(0) {
                failures.push(format!("{name}: ms bench failed\n{err}"));
            }
            continue;
        }
        let (code, _, err) = ms(&["check", path], "", None);
        if code != Some(0) {
            failures.push(format!("{name}: ms check failed\n{err}"));
            continue;
        }
        if !example.spec.contains("\"mode\":\"run\"") {
            continue;
        }
        let spec = ms_json::parse(&example.spec).unwrap_or_else(|e| panic!("{name}: {e}"));
        let mut cases = vec![spec.clone()];
        cases.extend(
            spec.get("cases")
                .and_then(Json::as_array)
                .unwrap_or_default()
                .iter()
                .cloned(),
        );
        for (i, case) in cases.iter().enumerate() {
            let case_dir = dir.join(format!("run{n}-{i}"));
            if let Some(problem) = run_case(path, &case_dir, case) {
                failures.push(format!("{name}: case {i}: {problem}"));
            }
        }
    }
    fs::remove_dir_all(&dir).ok();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn marked_tutorial_examples_compile_and_pass() {
    let all = examples();
    assert!(all.len() >= 20, "found only {} examples", all.len());
    verify(&all, "doc-examples");
}

/// Every `manuscript` fence in a standard-library comment carries a marker:
/// a complete example is checked (or run); a snippet says `"mode":"fragment"`.
#[test]
fn stdlib_comment_examples_are_marked_and_pass() {
    let all = examples_in(&repo_files("stdlib", "ms"), true);
    assert!(all.len() >= 10, "found only {} examples", all.len());
    let unmarked: Vec<String> = all
        .iter()
        .filter(|e| e.spec.is_empty())
        .map(|e| format!("{}:{}", e.file.display(), e.line))
        .collect();
    assert!(
        unmarked.is_empty(),
        "add `<!-- manuscript-example: {{\"mode\":\"check\"}} -->` (or \"fragment\") above each fence:\n{}",
        unmarked.join("\n")
    );
    verify(&all, "stdlib-examples");
}
