//! `ms search_symbol` finds project declarations with their uses, then standard-library symbols.

use std::process::Command;

#[test]
fn symbol_limit_bounds_the_combined_result_list() {
    let dir = std::env::temp_dir().join(format!("ms-cli-search-limit-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    for (fixture, project_total) in [("", 0), ("partial.ms", 1), ("lengths.ms", 12)] {
        if !fixture.is_empty() {
            std::fs::copy(
                std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                    .join("tests/search_symbol")
                    .join(fixture),
                dir.join("lengths.ms"),
            )
            .unwrap();
        }
        for (limit, expected) in [("1", 1), ("2", 2), ("10", 10), ("11", 10)] {
            let (status, out) = ms(&dir, &["length", "--limit", limit, "--json"]);
            assert_eq!(status, 0, "{out}");
            let document = ms_json::parse(&out).unwrap();
            let matches = document.get("matches").unwrap().as_array().unwrap();
            assert_eq!(
                matches.len(),
                expected,
                "project_total={project_total}, limit={limit}: {out}"
            );
            assert_eq!(
                document.get("project_total").unwrap().as_i64(),
                Some(project_total)
            );
            let projects = (project_total as usize).min(expected);
            assert!(
                matches[..projects]
                    .iter()
                    .all(|entry| entry.get("origin").unwrap().as_str() == Some("project"))
            );
            assert!(
                matches[projects..]
                    .iter()
                    .all(|entry| entry.get("origin").unwrap().as_str() == Some("std"))
            );
        }
        let (status, out) = ms(&dir, &["length", "--limit", "1"]);
        assert_eq!(status, 0, "{out}");
        assert_eq!(
            out.lines()
                .filter(|line| line.contains("  fn  ") || line.contains("  operation  "))
                .count(),
            1,
            "{out}"
        );
    }
    std::fs::remove_dir_all(dir).unwrap();
}

fn ms(dir: &std::path::Path, args: &[&str]) -> (i32, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("search_symbol")
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap();
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).into_owned(),
    )
}

#[test]
fn search_symbol_describes_project_and_standard_symbols() {
    let dir = std::env::temp_dir().join(format!("ms-cli-search-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(
        dir.join("a.ms"),
        "fn parse_config(text: String) Int:\n    return 1\n\nfn main() Int:\n    return parse_config(\"x\")\n",
    )
    .unwrap();

    let (status, out) = ms(&dir, &["parse_config"]);
    assert_eq!(status, 0);
    assert!(out.starts_with("parse_config  fn  a.ms:1:4\n"), "{out}");
    assert!(out.contains("  used (1): a.ms:5:12\n"), "{out}");

    let (_, out) = ms(&dir, &["--json", "parseconfig"]);
    assert!(out.contains("\"project_total\": 1"), "{out}");
    assert!(out.contains("\"origin\": \"project\""), "{out}");

    let (_, out) = ms(&dir, &["read", "file", "lines"]);
    assert!(out.contains("details: ms search_symbol"), "{out}");

    let (_, out) = ms(&dir, &["zzzzzzzz"]);
    assert!(
        out.starts_with("No project or standard-library symbol like"),
        "{out}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}
