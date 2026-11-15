//! Packages: `ms fetch` pins a git dependency, and every other command then works offline.

use crate::common::scratch;
use std::path::Path;
use std::process::{Command, Output};

fn ms(dir: &Path, cache: &Path, args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_ms"))
        .args(args)
        .current_dir(dir)
        .env("MS_PACKAGE_CACHE", cache)
        .output()
        .unwrap()
}

fn git(dir: &Path, args: &[&str]) {
    let status = Command::new("git")
        .args([
            "-c",
            "user.email=t@t",
            "-c",
            "user.name=t",
            "-c",
            "commit.gpgsign=false",
        ])
        .args(args)
        .current_dir(dir)
        .status()
        .unwrap();
    assert!(status.success(), "git {args:?}");
}

/// A git repository holding a package, tagged `v1.0.0`.
fn package(dir: &Path, manifest_extra: &str, source: &str) -> String {
    std::fs::create_dir_all(dir.join("src")).unwrap();
    std::fs::write(
        dir.join("ms.toml"),
        format!("[project]\nname = \"lib\"\nsource = \"src\"\n{manifest_extra}"),
    )
    .unwrap();
    std::fs::write(dir.join("src/lib.ms"), source).unwrap();
    git(dir, &["init", "-q", "."]);
    git(dir, &["add", "."]);
    git(dir, &["commit", "-q", "-m", "init"]);
    git(dir, &["tag", "v1.0.0"]);
    let path = dir.to_string_lossy().replace('\\', "/");
    let slash = if path.starts_with('/') { "" } else { "/" };
    format!("file://{slash}{path}#v1.0.0")
}

fn app(dir: &Path, dependencies: &str) {
    std::fs::create_dir_all(dir.join("src")).unwrap();
    std::fs::write(
        dir.join("ms.toml"),
        format!(
            "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n\n{dependencies}"
        ),
    )
    .unwrap();
    std::fs::write(dir.join("src/main.ms"), include_str!("packages/main.ms")).unwrap();
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[test]
fn fetch_pins_a_package_and_checks_work_offline() {
    let root = scratch("packages");
    let (cache, lib, project) = (root.join("cache"), root.join("lib"), root.join("app"));
    let spec = package(
        &lib,
        "effects = \"std.net.*\"\n",
        include_str!("packages/greet_net.ms"),
    );
    app(
        &project,
        &format!("[dependencies]\n\"@lib\" = \"{spec}\"\n\n[effects]\n\"@lib\" = \"std.net.*\"\n"),
    );

    let unlocked = ms(&project, &cache, &["check", "ms.toml"]);
    assert!(!unlocked.status.success());
    assert!(
        stderr(&unlocked).contains("run `ms fetch`"),
        "{}",
        stderr(&unlocked)
    );

    let fetched = ms(&project, &cache, &["fetch"]);
    assert!(fetched.status.success(), "{}", stderr(&fetched));
    let lock = std::fs::read_to_string(project.join("ms.lock")).unwrap();
    assert!(
        lock.contains("\"@lib\" = ") && lock.contains(" sha256:"),
        "{lock}"
    );

    // The source repository is gone: a locked check needs no network and no git.
    std::fs::rename(&lib, root.join("gone")).unwrap();
    let checked = ms(&project, &cache, &["check", "ms.toml"]);
    assert!(checked.status.success(), "{}", stderr(&checked));

    // A cached file edited after the fetch no longer matches the lock.
    let lib_file = std::fs::read_dir(&cache)
        .unwrap()
        .flatten()
        .map(|e| e.path().join("src/lib.ms"))
        .find(|p| p.is_file())
        .unwrap();
    let mut permissions = std::fs::metadata(&lib_file).unwrap().permissions();
    #[allow(clippy::permissions_set_readonly_false)]
    permissions.set_readonly(false);
    std::fs::set_permissions(&lib_file, permissions).unwrap();
    std::fs::write(
        &lib_file,
        "export fn greet(name: String) String:\n    return name\n",
    )
    .unwrap();
    let tampered = ms(&project, &cache, &["check", "ms.toml"]);
    assert!(!tampered.status.success());
    assert!(
        stderr(&tampered).contains("does not match ms.lock"),
        "{}",
        stderr(&tampered)
    );
}

#[test]
fn a_package_needs_the_importer_to_allow_its_effects() {
    let root = scratch("package-effects");
    let (cache, lib, project) = (root.join("cache"), root.join("lib"), root.join("app"));
    let spec = package(
        &lib,
        "effects = \"std.net.*\"\n",
        include_str!("packages/greet.ms"),
    );
    app(
        &project,
        &format!("[dependencies]\n\"@lib\" = \"{spec}\"\n"),
    );
    let fetched = ms(&project, &cache, &["fetch"]);
    assert!(fetched.status.success(), "{}", stderr(&fetched));
    let checked = ms(&project, &cache, &["check", "ms.toml"]);
    assert!(!checked.status.success());
    assert!(
        stderr(&checked).contains("does not allow"),
        "{}",
        stderr(&checked)
    );
}

/// A project that depends on a package holding `source`, fetched and then checked.
fn checked_with(name: &str, manifest_extra: &str, source: &str, allowed: &str) -> Output {
    let root = scratch(name);
    let (cache, lib, project) = (root.join("cache"), root.join("lib"), root.join("app"));
    let spec = package(&lib, manifest_extra, source);
    let effects = if allowed.is_empty() {
        String::new()
    } else {
        format!("\n[effects]\n\"@lib\" = \"{allowed}\"\n")
    };
    app(
        &project,
        &format!("[dependencies]\n\"@lib\" = \"{spec}\"\n{effects}"),
    );
    let fetched = ms(&project, &cache, &["fetch"]);
    assert!(fetched.status.success(), "{}", stderr(&fetched));
    ms(&project, &cache, &["check", "ms.toml"])
}

#[test]
fn the_checker_rejects_natives_in_a_package() {
    let checked = checked_with("package-native", "", include_str!("packages/native.ms"), "");
    assert!(!checked.status.success());
    assert!(
        stderr(&checked).contains("declares native"),
        "{}",
        stderr(&checked)
    );
}

#[test]
fn the_checker_holds_a_package_to_the_effects_it_declares() {
    // Reads a file but declares nothing: rejected even though the project allows everything.
    let pure = checked_with(
        "package-undeclared",
        "",
        include_str!("packages/reads.ms"),
        "*",
    );
    assert!(!pure.status.success());
    assert!(stderr(&pure).contains("std.fs.read"), "{}", stderr(&pure));
    assert!(
        stderr(&pure).contains("does not declare"),
        "{}",
        stderr(&pure)
    );
    // Declared and allowed: accepted. The package needs no `allow_effect` line of its own.
    let declared = checked_with(
        "package-declared",
        "effects = \"std.fs.read\"\n",
        include_str!("packages/reads.ms"),
        "std.fs.read",
    );
    assert!(declared.status.success(), "{}", stderr(&declared));
}

#[test]
fn a_tampered_lock_never_reaches_git_and_nested_packages_must_use_https() {
    let root = scratch("package-lock-injection");
    let cache = root.join("cache");
    let (lib, project) = (root.join("lib"), root.join("app"));
    let spec = package(&lib, "", include_str!("packages/greet.ms"));
    app(
        &project,
        &format!("[dependencies]\n\"@lib\" = \"{spec}\"\n"),
    );
    let hash = "0".repeat(64);
    let lock = format!("\"@lib\" = \"{spec} --upload-pack=touch_pwned sha256:{hash}\"\n");
    std::fs::write(project.join("ms.lock"), lock).unwrap();
    let fetched = ms(&project, &cache, &["fetch"]);
    assert!(!fetched.status.success());
    assert!(stderr(&fetched).contains("ms.lock"), "{}", stderr(&fetched));
    assert!(!project.join("touch_pwned").exists() && !root.join("touch_pwned").exists());

    // A package's own dependencies may not read the local machine.
    let (outer, nested_app) = (root.join("outer"), root.join("nested-app"));
    let nested = format!("[dependencies]\n\"@inner\" = \"{spec}\"\n");
    let outer_spec = package(&outer, &nested, include_str!("packages/greet.ms"));
    app(
        &nested_app,
        &format!("[dependencies]\n\"@lib\" = \"{outer_spec}\"\n"),
    );
    let fetched = ms(&nested_app, &cache, &["fetch"]);
    assert!(!fetched.status.success());
    assert!(
        stderr(&fetched).contains("https://"),
        "{}",
        stderr(&fetched)
    );
}
