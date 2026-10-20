//! Differential tests against the Go guide (`pkg/tooling/guide`) and docgen
//! outputs. They run when a Go toolchain is available (`MS_ORACLE_GO`, the
//! repository's `toolchain/go/bin/go`, or `go` on `PATH`) and are skipped
//! otherwise.

use ms_guide::json::Json;
use ms_guide::{Match, format_matches, search};
use std::collections::BTreeMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap()
}

fn go() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("MS_ORACLE_GO") {
        return Some(PathBuf::from(path));
    }
    let bundled = root().join("toolchain/go/bin/go");
    if bundled.exists() {
        return Some(bundled);
    }
    Command::new("go")
        .arg("version")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|_| PathBuf::from("go"))
}

/// Runs the Go oracle on `requests`, one per line, and returns the framed answers.
fn ask(go: &Path, requests: &[String]) -> BTreeMap<String, String> {
    let mut child = Command::new(go)
        .args(["run", "./crates/ms-guide/tests/testdata/oracle"])
        .current_dir(root())
        .env("GOFLAGS", "-mod=vendor")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("start the Go oracle");
    let mut stdin = child.stdin.take().unwrap();
    let input = requests.join("\n") + "\n";
    let writer = std::thread::spawn(move || stdin.write_all(input.as_bytes()).unwrap());
    let output = child.wait_with_output().expect("oracle output");
    writer.join().unwrap();
    assert!(output.status.success(), "the Go oracle failed");
    let text = String::from_utf8(output.stdout).expect("utf-8 oracle output");
    let mut answers = BTreeMap::new();
    for frame in text.split('\0').skip(1) {
        let (request, body) = frame.split_once('\n').expect("framed answer");
        let body = body.strip_suffix('\n').unwrap_or(body);
        answers.insert(request.to_string(), body.to_string());
    }
    answers
}

fn match_json(m: &Match) -> Json {
    Json::Obj(vec![
        ("Module".into(), Json::str(&m.module)),
        ("Name".into(), Json::str(&m.name)),
        ("Kind".into(), Json::str(&m.kind)),
        ("Signature".into(), Json::str(&m.signature)),
        ("Doc".into(), Json::str(&m.doc)),
        ("Path".into(), Json::str(&m.path)),
        ("Score".into(), Json::int(m.score)),
    ])
}

fn search_answer(limit: usize, query: &str) -> String {
    let matches = search(query, limit);
    let data = if matches.is_empty() {
        "null".to_string()
    } else {
        Json::Arr(matches.iter().map(match_json).collect()).pretty(ms_json::Escape::GoHtml)
    };
    format!("{data}\n{}", format_matches(query, &matches))
}

fn page_answer(path: &str) -> String {
    match ms_guide::page(path) {
        Ok(text) => text,
        Err(error) => format!("error: {error}"),
    }
}

fn bare(name: &str) -> &str {
    name.split('[').next().unwrap()
}

fn all_pages() -> Vec<String> {
    let mut paths = vec![];
    for module in ms_guide::standard_library() {
        let short = module
            .path
            .trim_start_matches("@std/")
            .trim_end_matches(".ms");
        paths.push(short.to_string());
        for d in &module.declarations {
            paths.push(format!("{short}.{}", bare(&d.name)));
            for m in &d.members {
                paths.push(format!("{short}.{}.{}", bare(&d.name), bare(&m.name)));
            }
        }
    }
    paths.extend(
        [
            "nosuch",
            "json.nosuch",
            "prelude.List.nosuch",
            "@std/json.ms",
            "@std/json.ms.parse",
            " json ",
            "",
            "prelude.List.sorted.extra",
        ]
        .map(String::from),
    );
    paths
}

const QUERIES: &[&str] = &[
    "jsn parse",
    "read file",
    "JSON PARSE",
    "http server",
    "parse_int",
    "sleep",
    "regex replace",
    "base64 encode",
    "sorted",
    "sort by",
    "read stdin lines",
    "uppercase",
    "split zzqxjv",
    "zzqxjv",
    "list",
    "   ",
    "fs.read",
    "how do i print to stdout",
    "env",
    "random",
    "concat strings",
    "delete key from map",
    "push",
    "size of list",
    "lowercase",
    "format time",
    "decimal",
    "toml parse",
    "websocket",
    "timeout",
    "hash sha256",
    "csv",
    "url parse",
    "path join",
    "write stdout",
];

#[test]
fn guide_matches_the_go_oracle() {
    let Some(go) = go() else {
        eprintln!("skipped: no Go toolchain for the oracle");
        return;
    };
    let mut requests = vec!["index".to_string(), "cheatsheet".to_string()];
    let pages = all_pages();
    requests.extend(pages.iter().map(|p| format!("page {p}")));
    for query in QUERIES {
        for limit in [0, 1, 3, 5, 25] {
            requests.push(format!("search {limit} {query}"));
        }
    }
    let answers = ask(&go, &requests);
    let mut failures = Vec::new();
    for request in &requests {
        let want = answers
            .get(request)
            .unwrap_or_else(|| panic!("no answer for {request:?}"));
        let got = match request.split_once(' ') {
            None if request == "index" => ms_guide::index(),
            None => ms_guide::cheatsheet().to_string(),
            Some(("page", path)) => page_answer(path),
            Some(("search", rest)) => {
                let (limit, query) = rest.split_once(' ').unwrap();
                search_answer(limit.parse().unwrap(), query)
            }
            Some(_) => unreachable!(),
        };
        if &got != want {
            failures.push(format!("{request}\n--- go\n{want}\n--- rust\n{got}"));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} answers differ; first:\n{}",
        failures.len(),
        requests.len(),
        failures.first().unwrap()
    );
}

/// The exports of one checked source file: the JSON snapshot, then each
/// module's portable Markdown; or `error: ...` when it does not check.
fn module_documentation_answer(path: &Path) -> String {
    let source = std::fs::read_to_string(path).unwrap();
    let name = path
        .strip_prefix(root())
        .unwrap()
        .to_string_lossy()
        .into_owned();
    let handle = std::thread::Builder::new()
        .stack_size(64 << 20)
        .spawn(move || {
            let file: std::sync::Arc<str> = std::sync::Arc::from(name.as_str());
            let module = match ms_syntax::parser::parse(&file, &source) {
                Ok(module) => module,
                Err(error) => return format!("error: {error}"),
            };
            let program = ms_check::check(
                vec![ms_check::load_module(&module)],
                ms_check::ImportMap::default(),
                ms_check::CheckOptions::default(),
            );
            if !program.diagnostics.is_empty() {
                return "error: diagnostics".to_string();
            }
            let modules = ms_guide::module_documentation(&program);
            let mut out = ms_guide::docgen::to_json(&modules);
            for module in &modules {
                out += &ms_guide::docgen::render_module(module);
            }
            out
        })
        .unwrap();
    handle.join().unwrap()
}

#[test]
fn module_documentation_matches_the_go_oracle() {
    let Some(go) = go() else {
        eprintln!("skipped: no Go toolchain for the oracle");
        return;
    };
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/testdata/moddoc");
    let mut files: Vec<PathBuf> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "ms"))
        .collect();
    files.sort();
    assert!(!files.is_empty());
    let requests: Vec<String> = files
        .iter()
        .map(|f| format!("moddoc {}", f.strip_prefix(root()).unwrap().display()))
        .collect();
    let answers = ask(&go, &requests);
    for (file, request) in files.iter().zip(&requests) {
        let want = &answers[request];
        // The Go oracle runs from the repository root, so file names in
        // diagnostics-free output never appear; only the exports do.
        let got = module_documentation_answer(file);
        assert!(
            !want.starts_with("error"),
            "{request}: the Go oracle rejected the fixture: {want}"
        );
        assert_eq!(&got, want, "{request}");
    }
}

#[test]
fn generated_site_files_match_the_go_oracle() {
    let Some(go) = go() else {
        eprintln!("skipped: no Go toolchain for the oracle");
        return;
    };
    let answers = ask(&go, &["site".to_string()]);
    let want = &answers["site"];
    let mut got = String::new();
    for (name, data) in ms_guide::docgen::site_files() {
        got += &format!(
            "{name} {}\n{}",
            data.len(),
            String::from_utf8(data).unwrap()
        );
    }
    assert!(&got == want, "generated files differ");
}
