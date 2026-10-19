//! Differential CLI tests against the Go `ms` oracle. They compare exit
//! status and stderr for usage errors that do not need an engine. Set
//! `MS_GO_ORACLE` to the Go binary (default `../../ms` from the workspace
//! root); the tests skip when it is absent.

use std::path::PathBuf;
use std::process::Command;

fn oracle() -> Option<PathBuf> {
    let path = std::env::var_os("MS_GO_ORACLE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../ms"));
    path.exists().then_some(path)
}

fn run(program: &std::path::Path, args: &[&str]) -> (i32, String, String) {
    let output = Command::new(program).args(args).output().unwrap();
    (
        output.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
    )
}

#[test]
fn usage_errors_match_go() {
    let Some(go) = oracle() else {
        eprintln!("skipping: no Go oracle");
        return;
    };
    let rust = PathBuf::from(env!("CARGO_BIN_EXE_ms"));
    let cases: &[&[&str]] = &[
        &["nosuch"],
        &["check"],
        &["build"],
        &["run", "--bogus", "x.ms"],
        &["fmt", "--bogus"],
        &["search_symbol", "--limit", "0", "x"],
        &["help", "a", "b"],
        &["version", "extra"],
        &["guide", "extra"],
        &["lsp", "extra"],
        &["--version"],
        &["version"],
    ];
    for args in cases {
        let (gs, gout, gerr) = run(&go, args);
        // The Rust implementation drops pprof, trace, debug and dap by design.
        let gerr = gerr.replace(", pprof, trace, debug, dap", "").replace(
            "All builds use the embedded Go toolchain; no Go installation is needed.",
            "Native builds link with the system C compiler driver (cc).",
        );
        let (rs, rout, rerr) = run(&rust, args);
        assert_eq!((gs, gout, gerr), (rs, rout, rerr), "mismatch for {args:?}");
    }
}

/// Source failures of `build`, `run` and `test` (loading, parsing, checking, the
/// entry rule, project manifests) report the same text and JSON as Go. These
/// stop before lowering, so they need no code generator.
#[test]
fn source_failures_match_go() {
    let Some(go) = oracle() else {
        eprintln!("skipping: no Go oracle");
        return;
    };
    let rust = PathBuf::from(env!("CARGO_BIN_EXE_ms"));
    let dir = std::env::temp_dir().join(format!("ms-source-failures-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("proj/src")).unwrap();
    std::fs::create_dir_all(dir.join("lib/src")).unwrap();
    let files: &[(&str, &str)] = &[
        ("type.ms", "export fn main() Int:\n    return \"x\"\n"),
        ("noexport.ms", "fn main() Int:\n    return 0\n"),
        ("parse.ms", "export fn main() Int {\n"),
        ("badret.ms", "export fn main() String:\n    return \"a\"\n"),
        ("constmain.ms", "export let main = 1\n"),
        ("generic.ms", "export fn main[T]() Int:\n    return 0\n"),
        (
            "missing.ms",
            "import { one } from \"./nope.ms\"\n\nexport fn main() Int:\n    return 0\n",
        ),
        (
            "a.ms",
            "import { x } from \"./b.ms\"\n\nexport fn main() Int:\n    return 0\n",
        ),
        (
            "b.ms",
            "import { x } from \"./a.ms\"\nexport fn y() Int:\n    return 0\n",
        ),
        ("badmanifest.toml", "[project]\nname = \"p\"\n"),
        (
            "proj/ms.toml",
            "[project]\nname = \"p\"\nsource = \"src\"\nentry = \"src/main.ms\"\n",
        ),
        (
            "proj/src/main.ms",
            "export fn main() Int:\n    return foo\n",
        ),
        (
            "lib/ms.toml",
            "[project]\nname = \"lib\"\nsource = \"src\"\n",
        ),
        ("lib/src/lib.ms", "export fn one() Int:\n    return 1\n"),
    ];
    for (name, text) in files {
        std::fs::write(dir.join(name), text).unwrap();
    }
    let cases: &[&[&str]] = &[
        &["build", "type.ms"],
        &["build", "noexport.ms"],
        &["build", "parse.ms"],
        &["build", "badret.ms"],
        &["build", "constmain.ms"],
        &["build", "generic.ms"],
        &["build", "missing.ms"],
        &["build", "a.ms"],
        &["build", "nofile.ms"],
        &["build", "badmanifest.toml"],
        &["build", "proj/ms.toml"],
        &["build", "lib/ms.toml"],
        &["build", "type.ms", "--json"],
        &["build", "proj/ms.toml", "--json"],
        &["build", "lib/ms.toml", "--json"],
        &["run", "type.ms"],
        &["run", "a.ms"],
        &["run", "proj/ms.toml"],
        &["test", "type.ms"],
        &["test", "type.ms", "--json"],
        &["test", "parse.ms", "--json"],
    ];
    for args in cases {
        let run_in = |program: &std::path::Path| {
            let output = Command::new(program)
                .args(*args)
                .current_dir(&dir)
                .output()
                .unwrap();
            (
                output.status.code().unwrap_or(-1),
                String::from_utf8_lossy(&output.stdout).into_owned(),
                String::from_utf8_lossy(&output.stderr).into_owned(),
            )
        };
        assert_eq!(run_in(&go), run_in(&rust), "mismatch for {args:?}");
    }
}
