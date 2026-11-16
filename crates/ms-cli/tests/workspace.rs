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
    file(root, "app/src/main.ms", include_str!("workspace/main.ms"));
    file(
        root,
        "libs/util/ms.toml",
        "[project]\nname = \"util\"\nsource = \"src\"\n",
    );
    file(
        root,
        "libs/util/src/greet.ms",
        include_str!("workspace/greet.ms"),
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
        include_str!("workspace/one.ms"),
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
        err(&denied).contains("workspace member util may use std.net.*")
            && err(&denied).contains("does not allow"),
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
fn members_share_one_lock_and_one_copy() {
    let root = scratch("workspace-lock");
    let (cache, lib) = (root.join("cache"), root.join("repo"));
    // A git package both members use.
    file(
        &lib,
        "ms.toml",
        "[project]\nname = \"lib\"\nsource = \"src\"\n",
    );
    file(&lib, "src/lib.ms", include_str!("workspace/one.ms"));
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
    // Both members name one repository at one tag, so the lock holds a single shared copy.
    let entries = lock.lines().filter(|l| l.contains("sha256:")).count();
    assert_eq!(entries, 1, "{lock}");
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

#[test]
fn fmt_and_test_at_the_root_run_on_every_member() {
    let root = scratch("workspace-fmt-test");
    let cache = root.join("cache");
    workspace(&root, "\"@util\" = { path = \"../libs/util\" }\n");
    file(
        &root,
        "app/src/a_test.ms",
        "test \"one\":\n\tif 1 != 1: return\n",
    );
    file(
        &root,
        "libs/util/src/b_test.ms",
        "test \"two\":\n\tif 2 != 2: return\n",
    );
    file(
        &root,
        "libs/util/src/messy.ms",
        "fn  messy()  Void:\n\tprint(\"x\")\n",
    );

    // fmt names the member file that needs formatting instead of failing on the root.
    let check = ms(&root, &cache, &["fmt", "--check", "ms.toml"]);
    assert!(!check.status.success(), "{}", err(&check));
    let text = err(&check);
    assert!(
        text.contains("messy.ms") && !text.contains("file not found"),
        "{text}"
    );
    let fmt = ms(&root, &cache, &["fmt", "ms.toml"]);
    assert!(fmt.status.success(), "{}", err(&fmt));
    let again = ms(&root, &cache, &["fmt", "--check", "ms.toml"]);
    assert!(again.status.success(), "{}", err(&again));

    // test runs each member as its own program: both tests run and pass.
    let test = ms(&root, &cache, &["test", "ms.toml"]);
    assert!(test.status.success(), "{}{}", out(&test), err(&test));
    let text = out(&test);
    assert!(text.contains("::one") && text.contains("::two"), "{text}");

    // verify covers every step at the root.
    let verify = ms(&root, &cache, &["verify", "ms.toml"]);
    assert!(verify.status.success(), "{}{}", out(&verify), err(&verify));

    // A failing member fails the run.
    file(
        &root,
        "libs/util/src/b_test.ms",
        "import panic from \"@std/core.ms\"\n\ntest \"two\":\n\treturn panic(message: \"no\")\n",
    );
    let failed = ms(&root, &cache, &["test", "ms.toml"]);
    assert!(!failed.status.success(), "{}", out(&failed));
}

#[test]
fn a_member_list_errors_name_members_and_allow_spaces_in_directories() {
    let root = scratch("workspace-member-list");
    let cache = root.join("cache");
    let check = |manifest: &str| {
        file(&root, "ms.toml", manifest);
        ms(&root, &cache, &["check"])
    };
    file(
        &root,
        "my app/ms.toml",
        "[project]\nname = \"my-app\"\nsource = \"src\"\n",
    );
    file(&root, "my app/src/x.ms", include_str!("workspace/one.ms"));
    let spaced = check("[workspace]\nmembers = [\"my app\"]\n");
    assert!(spaced.status.success(), "{}", err(&spaced));

    let twice = check("[workspace]\nmembers = [\"a\", \"a\"]\n");
    assert!(
        err(&twice).contains("member a is listed twice"),
        "{}",
        err(&twice)
    );
    let text = check("[workspace]\nmembers = \"a\"\n");
    assert!(
        err(&text).contains("members are a list of strings: [\"app\", \"libs/*\"]"),
        "{}",
        err(&text)
    );
    for manifest in [
        "[workspace]\nmembers = []\n",
        "[workspace]\n",
        "[workspace]\nmembers = [\"libs/*\"]\n",
    ] {
        std::fs::create_dir_all(root.join("libs")).unwrap();
        let none = check(manifest);
        assert!(!none.status.success(), "{manifest}");
        assert!(
            err(&none).contains("workspace lists no members"),
            "{manifest}: {}",
            err(&none)
        );
    }
}

#[test]
fn a_manifest_error_names_the_manifest_once_when_run_from_another_directory() {
    let root = scratch("workspace-error-path");
    let cache = root.join("cache");
    workspace(
        &root,
        "\"@wire\" = { url = \"https://example.invalid/acme/wire.git\", version = \"1\" }\n",
    );
    let check = ms(&root, &cache, &["check", "app/ms.toml"]);
    assert!(!check.status.success());
    let text = err(&check);
    assert!(text.contains("ms.lock has no copy"), "{text}");
    assert!(text.contains("app/ms.toml:1:1"), "{text}");
    assert!(!text.contains("app/app/ms.toml"), "{text}");
}

#[test]
fn a_member_diagnostic_keeps_the_logical_module_name_in_the_terminal_report() {
    let root = scratch("workspace-member-diagnostic");
    let cache = root.join("cache");
    workspace(&root, "\"@util\" = { path = \"../libs/util\" }\n");
    file(
        &root,
        "libs/util/src/greet.ms",
        "export fn greet() Int:\n    return \"x\"\n",
    );
    let check = ms(&root.join("app"), &cache, &["check", "ms.toml"]);
    let text = err(&check);
    assert!(text.contains("@workspace/util/src/greet.ms:2:12"), "{text}");
    assert!(!text.contains("app/@workspace"), "{text}");

    // From the root, `check` covers every member and places positions by collection.
    let json = ms(&root, &cache, &["check", "--json"]);
    let text = out(&json);
    assert!(
        text.contains("\"file\": \"@workspace/util/src/greet.ms\""),
        "{text}"
    );
}

#[test]
fn a_rebuild_notices_an_edit_in_a_path_dependency_member() {
    let root = scratch("workspace-rebuild");
    let cache = root.join("cache");
    workspace(&root, "\"@util\" = { path = \"../libs/util\" }\n");
    let app = root.join("app");
    let program = app.join(format!("program{}", std::env::consts::EXE_SUFFIX));
    let build = |expected: &str| {
        let built = ms(
            &app,
            &cache,
            &["build", "ms.toml", "-o", program.to_str().unwrap()],
        );
        assert!(built.status.success(), "{}", err(&built));
        let ran = Command::new(&program).output().unwrap();
        assert_eq!(out(&ran).trim(), expected);
    };
    build("hello workspace");
    file(
        &root,
        "libs/util/src/greet.ms",
        "export fn greet(name: String) String:\n    return f\"goodbye {name}\"\n",
    );
    build("goodbye workspace");
}

#[test]
fn init_workspace_creates_members_that_check_test_and_run() {
    let root = scratch("workspace-init");
    let cache = root.join("cache");
    let init = ms(&root, &cache, &["init", "--workspace", "team"]);
    assert!(init.status.success(), "{}", err(&init));
    let team = root.join("team");
    let check = ms(&team, &cache, &["check"]);
    assert!(check.status.success(), "{}", err(&check));
    let text = out(&check);
    assert!(
        text.contains("app/ms.toml") && text.contains("libs/greeter/ms.toml"),
        "{text}"
    );
    let test = ms(&team, &cache, &["test"]);
    assert!(test.status.success(), "{}", err(&test));
    // A fresh workspace passes the whole gate, formatting included.
    let verify = ms(&team, &cache, &["verify"]);
    assert!(verify.status.success(), "{}{}", out(&verify), err(&verify));
    let run = ms(&team, &cache, &["run", "app/ms.toml"]);
    assert_eq!(out(&run).trim(), "Hello, ms", "{}", err(&run));
    let again = ms(&team, &cache, &["init", "--workspace"]);
    assert!(!again.status.success());
    let both = ms(&root, &cache, &["init", "--lib", "--workspace", "x"]);
    assert_eq!(both.status.code(), Some(2));
}

#[test]
fn a_wildcard_skips_hidden_directories_and_a_member_lock_is_an_error() {
    let root = scratch("workspace-hidden-and-lock");
    let cache = root.join("cache");
    workspace(&root, "\"@util\" = { path = \"../libs/util\" }\n");
    // A hidden directory holding a manifest is not a member, even under `libs/*`.
    file(
        &root,
        "libs/.cache/ms.toml",
        "[project]\nname = \"util\"\nsource = \"src\"\n",
    );
    let ok = ms(&root.join("app"), &cache, &["check", "ms.toml"]);
    assert!(ok.status.success(), "{}", err(&ok));

    file(&root, "libs/util/ms.lock", "");
    let locked = ms(&root.join("app"), &cache, &["check", "ms.toml"]);
    assert!(!locked.status.success());
    assert!(
        err(&locked).contains("workspace member libs/util has its own ms.lock"),
        "{}",
        err(&locked)
    );
}
