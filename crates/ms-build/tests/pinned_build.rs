//! A pinned build keeps its own executable when another build replaces the shared output.
// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_build::{Profile, build_executable_pinned};
use ms_mir::parse::parse_module;
use ms_rt as _;
use std::process::Command;

#[path = "../../ms-clif/tests/support/mod.rs"]
mod support;

fn program(code: i64) -> String {
    format!(
        "module \"pin\"\nentry @main\nfn @main() -> int {{\nb0:\n  %r: int = iconst {code}\n  ret %r\n}}\n"
    )
}

#[test]
fn the_pin_keeps_a_build_s_own_executable_after_another_build_replaces_the_output() {
    let root = std::env::temp_dir().join(format!("ms-pinned-build-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    // The C runtime below has no process entry; static musl supplies one.
    let build = ms_build::BuildOptions {
        static_musl: true,
        ..ms_build::BuildOptions::default()
    };
    let c = root.join("start.c");
    std::fs::write(&c, "#include <stdint.h>\n#ifdef _WIN32\n#ifdef __aarch64__\nvoid __chkstk(void) {}\n#else\nvoid ___chkstk_ms(void) {}\n#endif\n#endif\nint msrt_start(int64_t (*entry)(void), const void *tables, int argc, char **argv) { return (int)entry(); }\n").unwrap();
    let runtime = root.join("start.o");
    assert!(
        support::cc()
            .args(["-O1", "-c", "-o"])
            .arg(&runtime)
            .arg(&c)
            .status()
            .unwrap()
            .success()
    );
    let output = root.join(format!("shared{}", std::env::consts::EXE_SUFFIX));
    let pin = root.join(format!("pin-a{}", std::env::consts::EXE_SUFFIX));
    let mut a = parse_module(&program(7)).unwrap();
    build_executable_pinned(
        &mut a,
        &output,
        Profile::Debug,
        &runtime,
        &[],
        &build,
        Some(&pin),
    )
    .unwrap();
    // Another build publishes to the same output before the first one is recorded.
    let mut b = parse_module(&program(9)).unwrap();
    build_executable_pinned(&mut b, &output, Profile::Debug, &runtime, &[], &build, None).unwrap();
    assert_eq!(Command::new(&output).status().unwrap().code(), Some(9));
    assert_eq!(Command::new(&pin).status().unwrap().code(), Some(7));
    let _ = std::fs::remove_dir_all(&root);
}
