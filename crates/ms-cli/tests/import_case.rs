//! An import must name a file with its exact case on every platform: a program that resolves
//! through a case-insensitive filesystem (macOS, Windows) would otherwise break on Linux, and
//! two spellings of one file would load as two modules.
use crate::common;
use std::process::Command;

#[test]
fn an_import_with_the_wrong_case_is_not_found_on_any_platform() {
    let dir = common::scratch("import-case");
    std::fs::write(dir.join("util.ms"), "export fn one() Int:\n\treturn 1\n").unwrap();
    for (name, spelling) in [
        ("exact", "./util.ms"),
        ("upper", "./UTIL.ms"),
        ("title", "./Util.ms"),
    ] {
        let main = dir.join(format!("{name}.ms"));
        std::fs::write(
            &main,
            format!("import one from \"{spelling}\"\nfn main() Void:\n\tprint(one())\n"),
        )
        .unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(["check", main.to_str().unwrap()])
            .output()
            .unwrap();
        let text = String::from_utf8_lossy(&output.stderr);
        if name == "exact" {
            assert!(output.status.success(), "{spelling}: {text}");
        } else {
            assert!(!output.status.success(), "{spelling} was accepted");
            assert!(text.contains("cannot find module"), "{spelling}: {text}");
        }
    }
}
