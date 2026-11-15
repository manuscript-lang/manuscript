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

#[test]
fn a_package_cannot_declare_natives_or_extra_permissions() {
    let root = scratch("package-rules");
    let cache = root.join("cache");
    for (name, source, message) in [
        ("native", include_str!("packages/native.ms"), "extern"),
        (
            "effect",
            include_str!("packages/effect.ms"),
            "does not declare",
        ),
    ] {
        let (lib, project) = (
            root.join(format!("{name}-lib")),
            root.join(format!("{name}-app")),
        );
        let spec = package(&lib, "", source);
        app(
            &project,
            &format!("[dependencies]\n\"@lib\" = \"{spec}\"\n"),
        );
        let fetched = ms(&project, &cache, &["fetch"]);
        assert!(!fetched.status.success(), "{name}");
        assert!(stderr(&fetched).contains(message), "{}", stderr(&fetched));
    }
}
