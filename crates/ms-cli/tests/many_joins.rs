//! A function with many join points compiles in reasonable time and keeps every value.

use std::fmt::Write as _;
use std::process::Command;

#[test]
fn many_joins_in_one_function() {
    let n: i64 = 300;
    let mut source = String::from(
        "from \"@std/io.ms\" import stdout\n\ndef id(x: Int) -> Int: x\n\nexport def main() -> Int:\n",
    );
    let value = |i: i64| i * 3 + i % 7;
    for i in 0..n {
        writeln!(source, "    let v{i} = id({i}) * 3 + {}", i % 7).unwrap();
    }
    source.push_str("    var t = 0\n");
    let mut expected = 0;
    for i in 0..n {
        let j = i * 7 % n;
        writeln!(source, "    t += v{i} % 11 + (v{j} if v{i} > 10 else 0)").unwrap();
        expected += value(i) % 11 + if value(i) > 10 { value(j) } else { 0 };
    }
    source.push_str("    stdout().write(f\"{t}\\n\").get()\n    return 0\n");
    let dir = std::env::temp_dir().join(format!("ms-many-joins-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("main.ms");
    std::fs::write(&path, source).unwrap();
    let out = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("run")
        .arg(&path)
        .args(["--build-type", "Debug"])
        .output()
        .unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        format!("{expected}\n")
    );
}
