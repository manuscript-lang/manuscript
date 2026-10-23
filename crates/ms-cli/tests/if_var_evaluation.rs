//! Mutable accessor borrows evaluate their receiver and key once, before branching.

use std::process::Command;

#[test]
fn mutable_accessor_evaluation_is_exactly_once() {
    let fixture = format!(
        "{}/tests/if_var_evaluation/evaluation.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    for build_type in ["Debug", "Release"] {
        let out = Command::new(env!("CARGO_BIN_EXE_ms"))
            .args(["run", &fixture, "--build-type", build_type])
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        assert_eq!(
            String::from_utf8_lossy(&out.stdout),
            "1 Map(key-1: [1, 9], key-2: [2])\n\
         missing 3\n\
         early 1 Map(key-1: [1, 9, 7], key-2: [2])\n\
         loop 3 Map(key-1: [1, 9, 7, 4], key-2: [2, 5])\n\
         1 [[[1, 9]], [[2]]]\n\
         1 [[[1, 9, 10]], [[2]]]\n\
         empty 1 [[], [[2]]]\n"
        );
    }
}
