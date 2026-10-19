//! The source tools (`lint`, `inspect`, `diagram`, `review`, `fmt --drop-labels`)
//! print the same bytes as the Go `ms`. Set `MS_GO_ORACLE` to the Go binary
//! (default `../../ms` from the workspace root); the tests skip when it is
//! absent.

use std::path::{Path, PathBuf};
use std::process::Command;

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
    match parse(text) {
        Some(Json::Obj(fields)) => Json::Obj(
            fields
                .into_iter()
                .filter(|(k, _)| k != "go_locals")
                .collect(),
        )
        .encode(),
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
