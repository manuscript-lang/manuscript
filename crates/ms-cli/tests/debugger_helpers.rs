//! The gdb and lldb display helpers decode strings, lists, optionals and enums by rules that
//! mirror the runtime's layouts; their pure-Python tests run here so a layout change that
//! breaks them fails CI. Python 3 is required (every CI runner has it).

use std::process::Command;

#[test]
fn display_helper_decoding_matches_the_layouts() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/../../tools/debugger");
    let python = ["python3", "python"]
        .into_iter()
        .find(|p| {
            Command::new(p)
                .arg("--version")
                .output()
                .is_ok_and(|o| o.status.success())
        })
        .expect("python 3 is needed to run tools/debugger/test_values.py");
    let out = Command::new(python)
        .args(["-B", "test_values.py"])
        .current_dir(dir)
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
}
