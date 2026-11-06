//! Pins and cache entries retain the executable and native companion from the same producer.
// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_build::{Profile, build_executable_pinned, cache, debug_companion_path, publish};
use ms_mir::parse::parse_module;
use ms_rt as _;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

// Keep fixture writes out of unrelated fixture forks (see engine/testing.rs).
static NATIVE_FIXTURE: Mutex<()> = Mutex::new(());

#[path = "../../ms-clif/tests/support/mod.rs"]
mod support;

fn program(code: i64) -> String {
    format!(
        "module \"pin\"\nentry @main\nfn @main() -> int {{\nb0:\n  %r: int = iconst {code}\n  ret %r\n}}\n"
    )
}

fn fixture(name: &str) -> (PathBuf, PathBuf, PathBuf, ms_build::BuildOptions) {
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!(
        "ms-build-debug-pinned-{name}-{}-{nonce}",
        std::process::id()
    ));
    std::fs::create_dir(&root).unwrap();
    // The C runtime has no process entry; static musl supplies one on Linux.
    let build = ms_build::BuildOptions {
        static_musl: cfg!(target_os = "linux"),
        lld: std::env::var_os("MS_LLD").map(PathBuf::from),
        ..ms_build::BuildOptions::default()
    };
    let c = root.join("start.c");
    std::fs::write(&c, "#include <stdint.h>\n#ifdef _WIN32\n#ifdef __aarch64__\nvoid __chkstk(void) {}\n#else\nvoid ___chkstk_ms(void) {}\n#endif\n#endif\nint msrt_start(int64_t (*entry)(void), const void *tables, int argc, char **argv) { return (int)entry(); }\n").unwrap();
    let runtime = root.join("start.o");
    // Real runtime DWARF makes dsymutil produce a dSYM even though the MIR has no source rows.
    let compiled = support::cc()
        .args(["-g", "-O1", "-c", "-o"])
        .arg(&runtime)
        .arg(&c)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    (root, c, runtime, build)
}

fn executable(root: &Path, name: &str) -> PathBuf {
    root.join(format!("{name}{}", std::env::consts::EXE_SUFFIX))
}

fn build(
    code: i64,
    output: &Path,
    pin: &Path,
    runtime: &Path,
    options: &ms_build::BuildOptions,
) -> Result<ms_build::Backend, String> {
    let mut module = parse_module(&program(code)).unwrap();
    build_executable_pinned(
        &mut module,
        output,
        Profile::Debug,
        runtime,
        &[],
        options,
        Some(pin),
    )
}

fn exits(path: &Path, expected: i32) {
    assert_eq!(
        Command::new(path).status().unwrap().code(),
        Some(expected),
        "{}",
        path.display()
    );
}

#[derive(Debug, PartialEq, Eq)]
struct CompanionIdentity {
    uuids: Vec<(String, String)>,
    dwarf: Vec<u8>,
}

fn uuids(path: &Path) -> Vec<(String, String)> {
    let tool = std::env::var("LLVM_DWARFDUMP").unwrap_or_else(|_| "llvm-dwarfdump".into());
    let result = Command::new(&tool).arg("--uuid").arg(path).output().expect(
        "native macOS companion identity validation requires LLVM_DWARFDUMP or llvm-dwarfdump",
    );
    assert!(
        result.status.success(),
        "dwarfdump {}: {}",
        path.display(),
        String::from_utf8_lossy(&result.stderr)
    );
    let text = String::from_utf8(result.stdout).unwrap();
    let mut ids: Vec<_> = text
        .lines()
        .filter_map(|line| {
            let mut cells = line.split_whitespace();
            if cells.next()? != "UUID:" {
                return None;
            }
            Some((cells.next()?.to_string(), cells.next()?.to_string()))
        })
        .collect();
    assert!(
        !ids.is_empty(),
        "dwarfdump found no UUID in {}: {text}",
        path.display()
    );
    ids.sort();
    ids
}

fn companion_identity(executable: &Path, bundle: Option<&Path>) -> Option<CompanionIdentity> {
    let bundle = bundle?;
    assert!(
        bundle.is_dir(),
        "native macOS identity coverage requires a generated dSYM at {}; install dsymutil rather than treating an absent companion as a pass",
        bundle.display()
    );
    let resources: Vec<_> = std::fs::read_dir(bundle.join("Contents/Resources/DWARF"))
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .collect();
    assert_eq!(resources.len(), 1, "{}", bundle.display());
    let executable_ids = uuids(executable);
    assert_eq!(
        executable_ids,
        uuids(&resources[0]),
        "executable and companion must describe the same native artifact"
    );
    Some(CompanionIdentity {
        uuids: executable_ids,
        dwarf: std::fs::read(&resources[0]).unwrap(),
    })
}

fn producer_identity(executable: &Path) -> Option<CompanionIdentity> {
    let companion = debug_companion_path(executable);
    assert_eq!(
        companion.is_some(),
        cfg!(target_os = "macos"),
        "native companion platform contract"
    );
    let identity = companion_identity(executable, companion.as_deref());
    if let Some(bundle) = companion {
        assert!(
            bundle
                .join("Contents/Resources/DWARF")
                .join(executable.file_name().unwrap())
                .is_file(),
            "the native companion resource must match its executable's basename"
        );
    }
    identity
}

fn no_build_stages(root: &Path) {
    assert!(
        std::fs::read_dir(root).unwrap().all(|entry| !entry
            .unwrap()
            .file_name()
            .to_string_lossy()
            .starts_with(".ms-build-")),
        "a private native build stage leaked in {}",
        root.display()
    );
}

#[test]
fn the_pin_keeps_a_build_s_own_executable_after_another_build_replaces_the_output() {
    let _native = NATIVE_FIXTURE
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let (root, source, runtime, options) = fixture("identity");
    let output = executable(&root, "shared");
    let pin_a = executable(&root, "pin-a");
    let pin_b = executable(&root, "pin-b");
    let backend_a = build(7, &output, &pin_a, &runtime, &options).unwrap();
    exits(&output, 7);
    exits(&pin_a, 7);
    let bytes_a = std::fs::read(&output).unwrap();
    let identity_a = producer_identity(&output);
    assert_eq!(producer_identity(&pin_a), identity_a);

    // B replaces the public executable and companion before A's private artifacts are recorded.
    let backend_b = build(9, &output, &pin_b, &runtime, &options).unwrap();
    exits(&output, 9);
    exits(&pin_a, 7);
    exits(&pin_b, 9);
    let bytes_b = std::fs::read(&output).unwrap();
    let identity_b = producer_identity(&output);
    assert_eq!(producer_identity(&pin_a), identity_a);
    assert_eq!(producer_identity(&pin_b), identity_b);
    assert_ne!(bytes_a, bytes_b);
    if let (Some(a), Some(b)) = (&identity_a, &identity_b) {
        assert_ne!(
            a.uuids, b.uuids,
            "the two actual executables must have different native UUIDs"
        );
        assert_ne!(a.dwarf, b.dwarf, "the two generated companions must differ");
    } else {
        assert!(identity_a.is_none() && identity_b.is_none());
        eprintln!(
            "{} has no separate debug companion; native executable and cache provenance are still checked",
            std::env::consts::OS
        );
    }
    let directory = root.join("cache");
    let sources = [source];
    for (key, pin, backend) in [("a", &pin_a, backend_a), ("b", &pin_b, backend_b)] {
        let companion = debug_companion_path(pin);
        cache::store(
            &directory,
            key,
            root.to_str().unwrap(),
            backend,
            &sources,
            pin,
            companion.as_deref(),
        );
    }
    for (key, expected, bytes, identity, backend) in [
        ("a", 7, &bytes_a, &identity_a, backend_a),
        ("b", 9, &bytes_b, &identity_b, backend_b),
    ] {
        let entry =
            cache::lookup(&directory, key).expect("a native cache entry must have been recorded");
        assert_eq!(entry.backend, backend);
        let cached_executable = directory
            .join(key)
            .join(format!("exe-{}", backend.as_str()));
        assert_eq!(std::fs::read(&cached_executable).unwrap(), *bytes);
        let cached_companion =
            debug_companion_path(&output).map(|_| directory.join(key).join("companion"));
        assert_eq!(
            companion_identity(&cached_executable, cached_companion.as_deref()).as_ref(),
            identity.as_ref()
        );
        let restored = executable(&root, &format!("restored-{key}"));
        let restored_companion = debug_companion_path(&restored);
        assert!(entry.restore(&restored, restored_companion.as_deref()));
        assert_eq!(std::fs::read(&restored).unwrap(), *bytes);
        exits(&restored, expected);
        assert_eq!(producer_identity(&restored).as_ref(), identity.as_ref());
        publish(&restored, &output).unwrap();
        exits(&output, expected);
        assert_eq!(std::fs::read(&output).unwrap(), *bytes);
        assert_eq!(producer_identity(&output).as_ref(), identity.as_ref());
    }
    no_build_stages(&root);
    // Retain actual native artifacts for the platform validation evidence collector.
    eprintln!("pinned native identity evidence: {}", root.display());
}

#[test]
fn an_obstructed_pin_preserves_the_previous_native_output_and_companion() {
    let _native = NATIVE_FIXTURE
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let (root, _, runtime, options) = fixture("pin-error");
    let output = executable(&root, "shared");
    let pin = executable(&root, "pin-a");
    build(7, &output, &pin, &runtime, &options).unwrap();
    let previous = std::fs::read(&output).unwrap();
    let identity = producer_identity(&output);
    let obstruction = root.join("obstructed-pin");
    std::fs::create_dir(&obstruction).unwrap();
    let sentinel = obstruction.join("sentinel");
    std::fs::write(&sentinel, b"the pin directory belongs to another owner").unwrap();
    let error = build(9, &output, &obstruction, &runtime, &options).unwrap_err();
    assert!(error.contains("obstructed-pin"), "{error}");
    exits(&output, 7);
    assert_eq!(std::fs::read(&output).unwrap(), previous);
    assert_eq!(producer_identity(&output), identity);
    assert!(obstruction.is_dir());
    assert_eq!(
        std::fs::read(&sentinel).unwrap(),
        b"the pin directory belongs to another owner"
    );
    no_build_stages(&root);
}
