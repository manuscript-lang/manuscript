//! Workspaces: members import one another by path, one `ms.lock` covers every member, and a
//! command aimed at a workspace root with no `[project]` means every member.

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

fn file(dir: &Path, name: &str, text: &str) {
    let path = dir.join(name);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, text).unwrap();
}

fn out(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn err(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

/// `app` imports `@util` by path; `util` is a library. The root holds only `[workspace]`.
fn workspace(root: &Path, app_dependencies: &str) {
    file(
        root,
        "ms.toml",
        "[workspace]\nmembers = [\"app\", \"libs/*\"]\n",
    );
    file(
        root,
        "app/ms.toml",
        &format!(
            "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n\n[dependencies]\n{app_dependencies}"
        ),
    );
    file(
        root,
        "app/src/main.ms",
        "import greet from \"@util/greet.ms\"\n\nfn main() Void:\n    print(greet(\"workspace\"))\n",
    );
    file(
        root,
        "libs/util/ms.toml",
        "[project]\nname = \"util\"\nsource = \"src\"\n",
    );
    file(
        root,
        "libs/util/src/greet.ms",
        "export fn greet(name: String) String:\n    return \"hello {name}\"\n",
    );
}

#[test]
fn a_member_imports_another_by_path_and_the_root_names_every_member() {
    let root = scratch("workspace-path");
    let cache = root.join("cache");
    workspace(&root, "\"@util\" = { path = \"../libs/util\" }\n");

    // The member builds and runs from inside its directory.
    let run = ms(&root.join("app"), &cache, &["run", "ms.toml"]);
    assert!(run.status.success(), "{}", err(&run));
    assert_eq!(out(&run).trim(), "hello workspace");

    // The root checks every member, and each is listed.
    let check = ms(&root, &cache, &["check", "ms.toml"]);
    assert!(check.status.success(), "{}", err(&check));
    let text = out(&check);
    assert!(
        text.contains("app/ms.toml") && text.contains("libs/util/ms.toml"),
        "{text}"
    );

    // Commands that make one program ask for a member.
    let build = ms(&root, &cache, &["build", "ms.toml"]);
    assert!(!build.status.success());
    let text = err(&build);
    assert!(
        text.contains("workspace root") && text.contains("app, util"),
        "{text}"
    );
}

#[test]
fn a_path_dependency_must_name_a_listed_member() {
    let root = scratch("workspace-unlisted");
    let cache = root.join("cache");
    workspace(&root, "\"@util\" = { path = \"../libs/util\" }\n");
    file(
        &root,
        "libs/other/ms.toml",
        "[project]\nname = \"other\"\nsource = \"src\"\n",
    );
    file(
        &root,
        "libs/other/src/x.ms",
        "export fn x() Int:\n    return 1\n",
    );
    file(
        &root,
        "ms.toml",
        "[workspace]\nmembers = [\"app\", \"libs/util\"]\n",
    );
    file(
        &root,
        "app/ms.toml",
        "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n\n[dependencies]\n\"@util\" = { path = \"../libs/other\" }\n",
    );
    let check = ms(&root.join("app"), &cache, &["check", "ms.toml"]);
    assert!(!check.status.success());
    assert!(
        err(&check).contains("not a workspace member"),
        "{}",
        err(&check)
    );

    // Outside any workspace a path dependency has nothing to resolve against.
    let alone = scratch("workspace-alone");
    workspace(&alone, "\"@util\" = { path = \"../libs/util\" }\n");
    std::fs::remove_file(alone.join("ms.toml")).unwrap();
    let check = ms(&alone.join("app"), &cache, &["check", "ms.toml"]);
    assert!(!check.status.success());
    assert!(
        err(&check).contains("no ancestor ms.toml has [workspace]"),
        "{}",
        err(&check)
    );
}

#[test]
fn members_cannot_form_a_cycle_and_names_are_unique() {
    let root = scratch("workspace-cycle");
    let cache = root.join("cache");
    workspace(&root, "\"@util\" = { path = \"../libs/util\" }\n");
    file(
        &root,
        "libs/util/ms.toml",
        "[project]\nname = \"util\"\nsource = \"src\"\n\n[dependencies]\n\"@app\" = { path = \"../../app\" }\n",
    );
    let check = ms(&root.join("app"), &cache, &["check", "ms.toml"]);
    assert!(!check.status.success());
    assert!(err(&check).contains("cycle"), "{}", err(&check));

    let twins = scratch("workspace-twins");
    workspace(&twins, "\"@util\" = { path = \"../libs/util\" }\n");
    file(
        &twins,
        "libs/util/ms.toml",
        "[project]\nname = \"app\"\nsource = \"src\"\n",
    );
    let check = ms(&twins, &cache, &["check", "ms.toml"]);
    assert!(!check.status.success());
    assert!(err(&check).contains("both named"), "{}", err(&check));
}

#[test]
fn a_member_holds_the_same_effect_rule_as_a_package() {
    let root = scratch("workspace-effects");
    let cache = root.join("cache");
    workspace(&root, "\"@util\" = { path = \"../libs/util\" }\n");
    file(
        &root,
        "libs/util/ms.toml",
        "[project]\nname = \"util\"\nsource = \"src\"\neffects = [\"std.net.*\"]\n",
    );
    let denied = ms(&root.join("app"), &cache, &["check", "ms.toml"]);
    assert!(!denied.status.success());
    assert!(
        err(&denied).contains("std.net.*") && err(&denied).contains("does not allow"),
        "{}",
        err(&denied)
    );

    file(
        &root,
        "app/ms.toml",
        "[project]\nname = \"app\"\nsource = \"src\"\nentry = \"src/main.ms\"\n\n[dependencies]\n\"@util\" = { path = \"../libs/util\" }\n\n[effects]\n\"@util\" = [\"std.net.*\"]\n",
    );
    let allowed = ms(&root.join("app"), &cache, &["check", "ms.toml"]);
    assert!(allowed.status.success(), "{}", err(&allowed));
}

#[test]
fn members_share_one_lock_keyed_by_member() {
    let root = scratch("workspace-lock");
    let (cache, lib) = (root.join("cache"), root.join("repo"));
    // A git package both members use.
    file(
        &lib,
        "ms.toml",
        "[project]\nname = \"lib\"\nsource = \"src\"\n",
    );
    file(&lib, "src/lib.ms", "export fn one() Int:\n    return 1\n");
    for args in [
        &["init", "-q", "."][..],
        &["add", "."],
        &["commit", "-q", "-m", "init"],
        &["tag", "v1.0.0"],
    ] {
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
            .current_dir(&lib)
            .status()
            .unwrap();
        assert!(status.success());
    }
    let path = lib.to_string_lossy().replace('\\', "/");
    let slash = if path.starts_with('/') { "" } else { "/" };
    let table = format!("{{ url = \"file://{slash}{path}\", tag = \"v1.0.0\" }}");
    workspace(
        &root,
        &format!("\"@util\" = {{ path = \"../libs/util\" }}\n\"@lib\" = {table}\n"),
    );
    file(
        &root,
        "libs/util/ms.toml",
        &format!(
            "[project]\nname = \"util\"\nsource = \"src\"\n\n[dependencies]\n\"@lib\" = {table}\n"
        ),
    );

    let install = ms(&root.join("app"), &cache, &["install"]);
    assert!(install.status.success(), "{}", err(&install));
    let lock = std::fs::read_to_string(root.join("ms.lock")).unwrap();
    assert!(
        lock.contains("\"app/@lib\"") && lock.contains("\"util/@lib\""),
        "{lock}"
    );
    assert!(!root.join("app/ms.lock").exists());

    // Offline, the workspace builds from the shared lock; the root checks every member.
    let check = ms(&root, &cache, &["check", "ms.toml"]);
    assert!(check.status.success(), "{}", err(&check));
    let run = ms(&root.join("app"), &cache, &["run", "ms.toml"]);
    assert!(run.status.success(), "{}", err(&run));

    // `ms add` belongs to a member.
    let add = ms(
        &root,
        &cache,
        &["add", "https://example.com/x.git", "--tag", "v1"],
    );
    assert!(!add.status.success());
    assert!(err(&add).contains("workspace root"), "{}", err(&add));
}
