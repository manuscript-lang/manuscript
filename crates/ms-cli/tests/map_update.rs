//! `m.add(k, m.get(k).get(d) <op> x)` on an Int-valued map is one lookup; the result must match
//! the same updates written so that the pattern is not recognised (a key held in another local).

use std::process::Command;

#[test]
fn fused_counter_updates_match_the_plain_form() {
    let file = format!(
        "{}/tests/map_update/fused_counter.ms",
        env!("CARGO_MANIFEST_DIR")
    );
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(["run", &file])
        .output()
        .unwrap();
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(out.status.code(), Some(0), "{text}");
}
