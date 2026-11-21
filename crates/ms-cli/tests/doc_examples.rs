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

/// The longest one `ms` command of an example may run.
const EXAMPLE_DEADLINE: std::time::Duration = std::time::Duration::from_secs(180);

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
/// comment blocks of `.ms` sources (`src/stdlib/`). With `all_fences`, a
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
    examples_in(&repo_files("documentation", "md"), true)
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
    // A hung example must fail this test, not hold the runner until the job is cancelled.
    let mut out = child.stdout.take().unwrap();
    let mut err = child.stderr.take().unwrap();
    let read_out = std::thread::spawn(move || {
        let mut text = Vec::new();
        out.read_to_end(&mut text).ok();
        text
    });
    let read_err = std::thread::spawn(move || {
        let mut text = Vec::new();
        err.read_to_end(&mut text).ok();
        text
    });
    let deadline = std::time::Instant::now() + EXAMPLE_DEADLINE;
    let mut timed_out = false;
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status.code();
        }
        if std::time::Instant::now() >= deadline {
            timed_out = true;
            child.kill().ok();
            child.wait().ok();
            break None;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    };
    if timed_out {
        // A grandchild may still hold the pipes open, so the readers are left to finish on their own.
        let stderr = format!(
            "killed: `ms {}` ran longer than {EXAMPLE_DEADLINE:?}",
            args.join(" ")
        );
        return (None, String::new(), stderr);
    }
    let stdout = String::from_utf8_lossy(&read_out.join().unwrap_or_default()).into_owned();
    let stderr = String::from_utf8_lossy(&read_err.join().unwrap_or_default()).into_owned();
    (status, stdout, stderr)
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
    // Debug (Cranelift) compiles several times faster than Release; both backends agree on every
    // corpus fixture (`make drift-check`), and these examples check what the documentation says.
    let mut argv = vec!["run", path, "--build-type", "Debug", "--"];
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

/// Splits a fragment into top-level declarations (kept as is) and statements (placed in
/// one function body, whose parameters are the fragment's `given` names) so that the whole
/// text parses as a module.
fn wrap_fragment(source: &str, given: &[String], context: &str) -> String {
    // A snippet shown inside a function keeps its indentation in the book; remove it here.
    let indent = source
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| l.len() - l.trim_start().len())
        .min()
        .unwrap_or(0);
    let dedented: String = source
        .lines()
        .map(|l| format!("{}\n", l.get(indent..).unwrap_or("")))
        .collect();
    let source = dedented.as_str();
    let mut decls = String::new();
    decls.push_str(context);
    if !context.is_empty() {
        decls.push('\n');
    }
    let mut body = String::new();
    let mut in_decl = false;
    for line in source.lines() {
        let starts_decl = ["import ", "type ", "enum ", "interface ", "fn ", "export "]
            .iter()
            .any(|k| line.starts_with(k));
        let continues = in_decl && (line.is_empty() || line.starts_with([' ', '\t', ')']));
        in_decl = starts_decl || continues;
        if in_decl {
            decls.push_str(line);
            decls.push('\n');
        } else {
            body.push_str("    ");
            body.push_str(line);
            body.push('\n');
        }
    }
    format!(
        "{decls}\nfn example({}) Void!:\n{body}    return\n",
        given.join(", ")
    )
}

/// `ms check` on a snippet. A snippet binds names it never reads, so "never read" findings do
/// not count. Returns the remaining diagnostic messages, empty when the snippet checks.
fn check_snippet(path: &str) -> Vec<String> {
    let (_, out, err) = ms(&["check", path, "--json"], "", None);
    let Ok(doc) = ms_json::parse(&out) else {
        return vec![err];
    };
    let diagnostics = doc
        .get("diagnostics")
        .and_then(Json::as_array)
        .unwrap_or_default();
    diagnostics
        .iter()
        .filter_map(|d| d.get("message").and_then(Json::as_str))
        .filter(|m| !m.contains("is never read"))
        .map(str::to_string)
        .collect()
}

/// Checks one example and returns what is wrong with it; examples are independent, so
/// `verify` runs them on several threads.
fn verify_one(n: usize, example: &Example, dir: &Path) -> Vec<String> {
    let mut failures = Vec::new();
    let path = dir.join(format!("example{n}.ms"));
    fs::write(&path, &example.source).unwrap();
    let path = path.to_str().unwrap();
    let name = format!("{}:{}", example.file.display(), example.line);
    if example.spec.contains("\"mode\":\"fragment\"") {
        // A fragment leaves names free. With a `given` list ("given":["raw: String"]) they become
        // parameters of the wrapper function and the fragment is type-checked, so its imports and
        // every standard name it uses must resolve. Without one it is only parsed: the
        // declarations stay at the top and the statements move into a function body.
        let spec = ms_json::parse(&example.spec).unwrap_or_else(|e| panic!("{name}: {e}"));
        let given = json_strings(spec.get("given"));
        let context = spec
            .get("context")
            .and_then(Json::as_str)
            .unwrap_or_default();
        fs::write(path, wrap_fragment(&example.source, &given, context)).unwrap();
        if spec.get("given").is_some() || !context.is_empty() {
            let found = check_snippet(path);
            if !found.is_empty() {
                failures.push(format!(
                    "{name}: fragment does not check\n{}",
                    found.join("\n")
                ));
            }
        } else {
            let (code, _, err) = ms(&["fmt", path], "", None);
            if code != Some(0) {
                failures.push(format!("{name}: fragment does not parse\n{err}"));
            }
        }
        return failures;
    }
    if example.spec.contains("\"mode\":\"error\"") {
        // A deliberately wrong sample: `ms check` must fail, and say `contains` when given.
        // `given` wraps it like a fragment.
        let spec = ms_json::parse(&example.spec).unwrap_or_else(|e| panic!("{name}: {e}"));
        if spec.get("given").is_some() {
            let given = json_strings(spec.get("given"));
            let context = spec
                .get("context")
                .and_then(Json::as_str)
                .unwrap_or_default();
            fs::write(path, wrap_fragment(&example.source, &given, context)).unwrap();
        }
        let (code, _, err) = ms(&["check", path], "", None);
        let want = spec.get("contains").and_then(Json::as_str);
        if code == Some(0) {
            failures.push(format!("{name}: expected an error, but ms check passed"));
        } else if let Some(want) = want
            && !err.contains(want)
        {
            failures.push(format!("{name}: error does not contain {want:?}\n{err}"));
        }
        return failures;
    }
    if example.spec.contains("\"mode\":\"test\"") {
        let (code, out, err) = ms(&["test", path, "--build-type", "Debug"], "", None);
        if code != Some(0) {
            failures.push(format!("{name}: ms test failed\n{out}\n{err}"));
        }
        return failures;
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
        return failures;
    }
    let (code, _, err) = ms(&["check", path], "", None);
    if code != Some(0) {
        failures.push(format!("{name}: ms check failed\n{err}"));
        return failures;
    }
    if !example.spec.contains("\"mode\":\"run\"") {
        return failures;
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
    failures
}

fn verify(examples: &[Example], label: &str) {
    let dir = std::env::temp_dir().join(format!("ms-{label}-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let next = std::sync::atomic::AtomicUsize::new(0);
    let failures = std::sync::Mutex::new(Vec::new());
    let threads = std::thread::available_parallelism().map_or(2, |n| n.get().min(8));
    std::thread::scope(|scope| {
        for _ in 0..threads {
            scope.spawn(|| {
                loop {
                    let n = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    let Some(example) = examples.get(n) else {
                        break;
                    };
                    let found = verify_one(n, example, &dir);
                    failures.lock().unwrap().extend(found);
                }
            });
        }
    });
    fs::remove_dir_all(&dir).ok();
    let mut failures = failures.into_inner().unwrap();
    failures.sort();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn marked_tutorial_examples_compile_and_pass() {
    let all = examples();
    assert!(all.len() >= 20, "found only {} examples", all.len());
    let unmarked: Vec<String> = all
        .iter()
        .filter(|e| e.spec.is_empty())
        .map(|e| format!("{}:{}", e.file.display(), e.line))
        .collect();
    assert!(
        unmarked.is_empty(),
        "add `<!-- manuscript-example: {{\"mode\":\"check\"}} -->` (or run, fragment with given, error) above each fence:\n{}",
        unmarked.join("\n")
    );
    verify(&all, "doc-examples");
}

/// Every `manuscript` fence in a standard-library comment carries a marker:
/// a complete example is checked (or run); a snippet says `"mode":"fragment"`.
#[test]
fn stdlib_comment_examples_are_marked_and_pass() {
    let all = examples_in(&repo_files("src/stdlib", "ms"), true);
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

/// README samples sit in `rust` fences (GitHub highlights those) and are not Markdown the book
/// checks, so they drift. Each must pass `ms check`; a `"mode":"error"` marker names the
/// diagnostic a deliberately wrong sample must give.
#[test]
fn readme_samples_check() {
    let readme = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../README.md");
    let text = fs::read_to_string(readme).unwrap();
    let lines: Vec<&str> = text.lines().collect();
    let dir = std::env::temp_dir().join(format!("ms-readme-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let mut failures = Vec::new();
    let mut count = 0;
    for (i, line) in lines.iter().enumerate() {
        if *line != "```rust" {
            continue;
        }
        count += 1;
        let source: Vec<&str> = lines[i + 1..]
            .iter()
            .copied()
            .take_while(|l| !l.starts_with("```"))
            .collect();
        let path = dir.join(format!("readme{count}.ms"));
        fs::write(&path, source.join("\n") + "\n").unwrap();
        let (code, _, err) = ms(&["check", path.to_str().unwrap()], "", None);
        let marker = i.checked_sub(1).and_then(|m| lines[m].strip_prefix(MARKER));
        let want = marker
            .and_then(|rest| ms_json::parse(rest.trim_end().trim_end_matches("-->").trim()).ok())
            .and_then(|spec| {
                spec.get("contains")
                    .and_then(Json::as_str)
                    .map(str::to_string)
            });
        match want {
            Some(text) if code == Some(0) || !err.contains(&text) => {
                failures.push(format!(
                    "README.md:{}: want an error containing {text:?}\n{err}",
                    i + 1
                ));
            }
            None if code != Some(0) => {
                failures.push(format!("README.md:{}: ms check failed\n{err}", i + 1));
            }
            _ => {}
        }
    }
    fs::remove_dir_all(&dir).ok();
    assert!(count >= 4, "found only {count} README samples");
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
