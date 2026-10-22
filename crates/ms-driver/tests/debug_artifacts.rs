//! Source attribution must survive the actual staged build and object cleanup.
// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_driver::{Profile, build_executable};
use ms_mir::parse::parse_module;
use ms_rt as _;
use std::path::Path;
use std::process::Command;

#[path = "../../ms-clif/tests/support/mod.rs"]
mod support;

fn tool(name: &str) -> String {
    let key = if name == "llvm-dwarfdump" {
        "LLVM_DWARFDUMP"
    } else {
        "LLVM_SYMBOLIZER"
    };
    std::env::var(key).unwrap_or_else(|_| name.into())
}

#[test]
fn final_build_keeps_source_lines_after_staging_and_object_cleanup() {
    let root = std::env::temp_dir().join(format!("ms-driver-debug-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let source = root.join("source with spaces.ms");
    std::fs::write(
        &source,
        "# source fixture\n# checked address is on this line\n",
    )
    .unwrap();
    let c = root.join("start.c");
    std::fs::write(&c, "#include <stdint.h>\n#ifdef _WIN32\n/* mingw's startup code asks for the stack probe; this runtime has no compiler-builtins. */\n#ifdef __aarch64__\nvoid __chkstk(void) {}\n#else\nvoid ___chkstk_ms(void) {}\n#endif\n#endif\nint msrt_start(int64_t (*entry)(void), const void *tables, int argc, char **argv) { return (int)entry(); }\n").unwrap();
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
    let text = format!(
        r#"module "driver_debug"
file 0 {:?}
entry @main
fn @plus(%x: int) -> int export inline(never) !0:1:1 {{
b0:
  %one: int = iconst 1
  %y: int = iadd %x, %one !0:2:1
  ret %y
}}
fn @main() -> int {{
b0:
  %x: int = iconst 41
  %r: int = call @plus(%x)
  ret %r
}}
"#,
        source.to_str().unwrap()
    );
    let output = root.join(format!(
        "final renamed program{}",
        std::env::consts::EXE_SUFFIX
    ));
    // Replacing an existing output also exercises replacement of its companion.
    for profile in [Profile::Debug, Profile::Release] {
        let mut module = parse_module(&text).unwrap();
        build_executable(&mut module, &output, profile, &runtime).unwrap();
        assert_eq!(Command::new(&output).status().unwrap().code(), Some(42));
        let companion = ms_clif::link::debug_companion_path(&output);
        let debug = if let Some(bundle) = &companion {
            let files: Vec<_> = std::fs::read_dir(bundle.join("Contents/Resources/DWARF"))
                .unwrap()
                .map(|e| e.unwrap().path())
                .collect();
            assert_eq!(files.len(), 1);
            assert_eq!(files[0].file_name(), output.file_name());
            files[0].clone()
        } else {
            output.clone()
        };
        let dump = Command::new(tool("llvm-dwarfdump"))
            .arg("--debug-line")
            .arg(&debug)
            .output()
            .unwrap();
        assert!(
            dump.status.success(),
            "{}",
            String::from_utf8_lossy(&dump.stderr)
        );
        let dump = String::from_utf8(dump.stdout).unwrap();
        std::fs::write(root.join(format!("driver-{profile:?}-lines.txt")), &dump).unwrap();
        let address = dump
            .lines()
            .find_map(|row| {
                let cells: Vec<_> = row.split_whitespace().collect();
                (cells.len() >= 4
                    && cells[0].starts_with("0x")
                    && cells[1] == "2"
                    && !cells.contains(&"end_sequence"))
                .then(|| cells[0].to_string())
            })
            .expect("final linked source row");
        let mut symbolizer = Command::new(tool("llvm-symbolizer"));
        symbolizer
            .arg(format!("--obj={}", output.display()))
            .args(["--functions=none", "--output-style=GNU"]);
        let got = symbolizer.arg(address).output().unwrap();
        assert!(
            got.status.success(),
            "{}",
            String::from_utf8_lossy(&got.stderr)
        );
        let location = String::from_utf8(got.stdout)
            .unwrap()
            .trim()
            .replace('\\', "/");
        let expected = format!("{}:2", source.display()).replace('\\', "/");
        assert_eq!(location, expected);
        for file in std::fs::read_dir(&root).unwrap() {
            assert!(
                !file
                    .unwrap()
                    .file_name()
                    .to_string_lossy()
                    .starts_with(".ms-build-"),
                "staged artifact left over"
            );
        }
    }
    // Preserve output/consumer evidence for the CI artifact uploader.
    assert!(Path::new(&output).exists());
}
