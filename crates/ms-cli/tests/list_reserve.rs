//! `List[T](reserve: n)` is an empty list with room for `n` items; negative and `none` reserve nothing.

use std::process::Command;

#[test]
fn reserved_lists_start_empty_and_grow() {
    let file = format!(
        "{}/tests/list_reserve/reserve.ms",
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
