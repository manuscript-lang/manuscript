//! Tutorial fences marked `manuscript-example` must still compile and pass.
//!
//! `test` examples run under `ms test`. `run` examples are type-checked, and
//! also executed with their `args`, `stdin` and `stdout` when they need
//! neither files nor an HTTP server.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const MARKER: &str = "<!-- manuscript-example: ";

struct Example {
    file: PathBuf,
    line: usize,
    spec: String,
    source: String,
}

fn markdown_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            markdown_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "md") {
            out.push(path);
        }
    }
}

fn examples() -> Vec<Example> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../documentation");
    let mut files = Vec::new();
    markdown_files(&root, &mut files);
    files.sort();
    let mut found = Vec::new();
    for file in files {
        let text = fs::read_to_string(&file).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        for (i, line) in lines.iter().enumerate() {
            let Some(rest) = line.strip_prefix(MARKER) else {
                continue;
            };
            let spec = rest.trim_end().trim_end_matches("-->").trim().to_string();
            let fence = lines.get(i + 1).copied().unwrap_or("");
            assert!(fence.starts_with("```manuscript"), "{file:?}:{}", i + 1);
            let body: Vec<&str> = lines[i + 2..]
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

/// The quoted strings of `"key":[..]`, or of `"key":".."` as a single item.
fn string_items(spec: &str, key: &str) -> Option<Vec<String>> {
    let rest = spec.split_once(&format!("\"{key}\":"))?.1;
    let (list, mut rest) = match rest.strip_prefix('[') {
        Some(r) => (true, r),
        None => (false, rest),
    };
    let mut items = Vec::new();
    loop {
        rest = rest.trim_start_matches([' ', ',']);
        let Some(r) = rest.strip_prefix('"') else {
            return Some(items);
        };
        let mut out = String::new();
        let mut chars = r.char_indices();
        let end = loop {
            match chars.next()? {
                (i, '"') => break i + 1,
                (_, '\\') => match chars.next()?.1 {
                    'n' => out.push('\n'),
                    other => out.push(other),
                },
                (_, c) => out.push(c),
            }
        };
        items.push(out);
        rest = &r[end..];
        if !list {
            return Some(items);
        }
    }
}

fn string_field(spec: &str, key: &str) -> Option<String> {
    string_items(spec, key)?.into_iter().next()
}

fn ms(args: &[&str], stdin: &str) -> (bool, String, String) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(stdin.as_bytes()).ok();
    let out = child.wait_with_output().unwrap();
    (
        out.status.success(),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    )
}

#[test]
fn marked_tutorial_examples_compile_and_pass() {
    let dir = std::env::temp_dir().join(format!("ms-doc-examples-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let mut failures = Vec::new();
    let all = examples();
    assert!(all.len() >= 20, "found only {} examples", all.len());
    for (n, example) in all.iter().enumerate() {
        let path = dir.join(format!("example{n}.ms"));
        fs::write(&path, &example.source).unwrap();
        let path = path.to_str().unwrap();
        let name = format!("{}:{}", example.file.display(), example.line);
        if example.spec.contains("\"mode\":\"test\"") {
            let (ok, _, err) = ms(&["test", path], "");
            if !ok {
                failures.push(format!("{name}: ms test failed\n{err}"));
            }
            continue;
        }
        let (ok, _, err) = ms(&["check", path], "");
        if !ok {
            failures.push(format!("{name}: ms check failed\n{err}"));
            continue;
        }
        let plain = !example.spec.contains("\"files\"")
            && !example.spec.contains("\"want_files\"")
            && !example.spec.contains("\"http\"");
        let top = example.spec.split("\"cases\"").next().unwrap_or("");
        let Some(want) = string_field(top, "stdout").filter(|_| plain) else {
            continue;
        };
        let given = string_items(top, "args").unwrap_or_default();
        let mut args = vec!["run", path, "--"];
        args.extend(given.iter().map(String::as_str));
        let stdin = string_field(top, "stdin").unwrap_or_default();
        let (ok, got, err) = ms(&args, &stdin);
        if !ok || got != want {
            failures.push(format!("{name}: want stdout {want:?}, got {got:?}\n{err}"));
        }
    }
    fs::remove_dir_all(&dir).ok();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
