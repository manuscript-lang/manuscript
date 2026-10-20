//! The source tools (`lint`, `inspect`, `diagram`, `review`, `fmt --drop-labels`)
//! print the same bytes as the Go `ms`. Set `MS_GO_ORACLE` to the Go binary
//! (default `../../ms` from the workspace root); the tests skip when it is
//! absent.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use ms_cli::json::{Json, parse};

fn oracle() -> Option<PathBuf> {
    let path = std::env::var_os("MS_GO_ORACLE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../ms"));
    path.canonicalize().ok()
}

fn run(program: &Path, dir: &Path, args: &[&str]) -> (i32, String, String) {
    let output = Command::new(program)
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap();
    (
        output.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    )
}

/// The Go inspector lists the lowering's local names; the Rust pipeline has none.
fn without_go_locals(text: &str) -> String {
    match parse(text).ok() {
        Some(Json::Obj(fields)) => Json::Obj(
            fields
                .into_iter()
                .filter(|(k, _)| k != "go_locals")
                .collect(),
        )
        .pretty_line(ms_json::Escape::GoHtml),
        _ => text.to_string(),
    }
}

fn write(dir: &Path, name: &str, text: &str) {
    let path = dir.join(name);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).unwrap();
}

fn project(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ms-cli-tooling-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    write(
        &dir,
        "ms.toml",
        "[project]\nname = \"rv\"\nsource = \"src\"\nentry = \"src/main.ms\"\n",
    );
    write(
        &dir,
        "src/lib.ms",
        "import { stdout } from \"@std/io.ms\"\n\nexport fn add(a: Int, b: Int) Int:\n    return a + b\n\nfn helper(x: Int) Int:\n    return x * 2\n",
    );
    write(
        &dir,
        "src/main.ms",
        "import { add } from \"./lib.ms\"\n\nexport fn main() Int:\n    let v = add(1, 2)\n    return v - 3 \n",
    );
    // The same project after a change: `add` gains an effect and a new result type.
    write(
        &dir,
        "change.patch",
        "--- a/src/lib.ms\n+++ b/src/lib.ms\n@@ -1,7 +1,8 @@\n import { stdout } from \"@std/io.ms\"\n \n-export fn add(a: Int, b: Int) Int:\n+export fn add(a: Int, b: Int) Float:\n+    stdout().write(\"adding\\n\")\n-    return a + b\n+    return 1.0\n \n fn helper(x: Int) Int:\n     return x * 2\n",
    );
    dir
}

#[test]
fn source_tools_match_go() {
    let Some(go) = oracle() else {
        eprintln!("skipping: no Go oracle");
        return;
    };
    let rust = PathBuf::from(env!("CARGO_BIN_EXE_ms"));
    let dir = project("tools");
    let cases: &[&[&str]] = &[
        &["check", "ms.toml"],
        &["check", "ms.toml", "--json"],
        &["check", "src"],
        &["check", "src/lib.ms"],
        &["check", "src/main.ms", "src/lib.ms", "--json"],
        &["check", "missing.ms"],
        &["lint", "ms.toml"],
        &["lint", "ms.toml", "--json"],
        &["lint", "src"],
        &["lint", "src/main.ms", "src/lib.ms", "--json"],
        &["lint", "missing.ms"],
        &["inspect", "missing.ms", "--json"],
        &["diagram", "ms.toml"],
        &["diagram", "ms.toml", "--format", "mermaid"],
        &["diagram", "ms.toml", "--view", "calls", "--depth", "2"],
        &["diagram", "ms.toml", "--view", "effects"],
        &[
            "diagram", "ms.toml", "--view", "modules", "--format", "mermaid",
        ],
        &["diagram", "ms.toml", "--entity", "add"],
        &["diagram", "ms.toml", "--view", "nonsense"],
        &["diagram", "ms.toml", "-o", "ms.toml"],
        &["review", "ms.toml"],
        &["review", "ms.toml", "--all", "--format", "markdown"],
        &["review", "ms.toml", "--json"],
        &["review", "ms.toml", "--diff", "change.patch"],
        &["review", "ms.toml", "--diff", "change.patch", "--json"],
        &[
            "review",
            "ms.toml",
            "--diff",
            "change.patch",
            "--explain",
            "1",
        ],
        &["review", "ms.toml", "--diff", "missing.patch"],
        &["review", "ms.toml", "--diff", "src/lib.ms"],
        &[
            "diagram",
            "ms.toml",
            "--view",
            "calls",
            "--diff",
            "change.patch",
        ],
        &["fmt", "--drop-labels", "--check", "src/missing.ms"],
    ];
    for args in cases {
        let expected = run(&go, &dir, args);
        let actual = run(&rust, &dir, args);
        assert_eq!(expected, actual, "mismatch for {args:?}");
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn inspect_matches_go_apart_from_go_locals() {
    let Some(go) = oracle() else {
        eprintln!("skipping: no Go oracle");
        return;
    };
    let rust = PathBuf::from(env!("CARGO_BIN_EXE_ms"));
    let dir = project("inspect");
    for args in [&["inspect", "ms.toml"][..], &["inspect", "src/lib.ms"]] {
        let (gs, gout, gerr) = run(&go, &dir, args);
        let (rs, rout, rerr) = run(&rust, &dir, args);
        assert_eq!(
            (gs, without_go_locals(&gout), gerr),
            (rs, without_go_locals(&rout), rerr),
            "mismatch for {args:?}"
        );
    }
    let _ = std::fs::remove_dir_all(&dir);
}

/// Run `<command> main.ms --watch`, save `edits` in turn (each waits for the
/// previous rerun), then interrupt it.
fn watched(program: &Path, command: &str, dir: &Path, edits: &[&str]) -> (i32, String, String) {
    let mut child = Command::new(program)
        .args([command, "main.ms", "--watch"])
        .current_dir(dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let (stdout, stderr) = (child.stdout.take().unwrap(), child.stderr.take().unwrap());
    let (sender, receiver) = std::sync::mpsc::channel();
    let readers: Vec<_> = [
        (0, Box::new(stdout) as Box<dyn Read + Send>),
        (1, Box::new(stderr)),
    ]
    .into_iter()
    .map(|(stream, mut pipe)| {
        let sender = sender.clone();
        std::thread::spawn(move || {
            let mut buffer = [0u8; 4096];
            let mut all = String::new();
            while let Ok(n) = pipe.read(&mut buffer) {
                if n == 0 {
                    break;
                }
                all.push_str(&String::from_utf8_lossy(&buffer[..n]));
                let _ = sender.send((stream, all.clone()));
            }
            all
        })
    })
    .collect();
    drop(sender);
    let mut seen = [String::new(), String::new()];
    let wait_for_runs = |runs: usize, seen: &mut [String; 2]| {
        let deadline = Instant::now() + Duration::from_secs(20);
        while seen[1].matches("ms: waiting for changes").count() < runs {
            let left = deadline.saturating_duration_since(Instant::now());
            let (stream, all) = receiver.recv_timeout(left).expect("watch output");
            seen[stream] = all;
        }
    };
    wait_for_runs(1, &mut seen);
    for (index, edit) in edits.iter().enumerate() {
        // The poll compares size and time; a longer file always differs.
        std::thread::sleep(Duration::from_millis(30));
        write(dir, "main.ms", edit);
        wait_for_runs(index + 2, &mut seen);
    }
    let kill = Command::new("kill")
        .args(["-INT", &child.id().to_string()])
        .status()
        .unwrap();
    assert!(kill.success());
    let status = child.wait().unwrap().code().unwrap_or(-1);
    let outputs: Vec<String> = readers.into_iter().map(|r| r.join().unwrap()).collect();
    (status, outputs[0].clone(), outputs[1].clone())
}

#[test]
fn watch_reruns_after_edits_like_go() {
    let Some(go) = oracle() else {
        eprintln!("skipping: no Go oracle");
        return;
    };
    let rust = PathBuf::from(env!("CARGO_BIN_EXE_ms"));
    let good = "export fn main() Int:\n    return 0\n";
    let bad = "export fn main() Int:\n    return \"text\"\n";
    let lint_bad = "export fn main() Int:\n    let unused = 1\n    return 0\n";
    for (command, edits) in [("check", vec![bad, good]), ("lint", vec![lint_bad, good])] {
        let mut results = Vec::new();
        for (name, program) in [("go", &go), ("rust", &rust)] {
            let dir = std::env::temp_dir().join(format!(
                "ms-cli-watch-{command}-{name}-{}",
                std::process::id()
            ));
            let _ = std::fs::remove_dir_all(&dir);
            write(&dir, "main.ms", good);
            let (status, out, err) = watched(program, command, &dir, &edits);
            let shown = dir.to_string_lossy().into_owned();
            results.push((
                status,
                out.replace(&shown, "DIR"),
                err.replace(&shown, "DIR"),
            ));
            let _ = std::fs::remove_dir_all(&dir);
        }
        assert_eq!(results[0].0, 130, "{command} status");
        assert_eq!(results[0], results[1], "{command} --watch differs");
    }
}
