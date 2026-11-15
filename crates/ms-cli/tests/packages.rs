//! Packages: `ms install` pins a git dependency, and every other command then works offline.

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

/// A dependency table, `{ url = "...", tag = "..." }`, for the `url#reference` spec a fixture returns.
fn table(spec: &str) -> String {
    let (url, reference) = spec.split_once('#').unwrap();
    let field = if reference.len() == 40 && reference.bytes().all(|b| b.is_ascii_hexdigit()) {
        "sha"
    } else {
        "tag"
    };
    format!("{{ url = \"{url}\", {field} = \"{reference}\" }}")
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
        "effects = [\"std.net.*\"]\n",
        include_str!("packages/greet_net.ms"),
    );
    app(
        &project,
        &format!(
            "[dependencies]\n\"@lib\" = {}\n\n[effects]\n\"@lib\" = [\"std.net.*\"]\n",
            table(&spec)
        ),
    );

    let unlocked = ms(&project, &cache, &["check", "ms.toml"]);
    assert!(!unlocked.status.success());
    assert!(
        stderr(&unlocked).contains("run `ms install`"),
        "{}",
        stderr(&unlocked)
    );

    let fetched = ms(&project, &cache, &["install"]);
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

    // A project path spelled like a package name could pass for package code.
    std::fs::create_dir(project.join("@lib")).unwrap();
    let clash = ms(&project, &cache, &["check", "ms.toml"]);
    assert!(!clash.status.success());
    assert!(
        stderr(&clash).contains("names starting with @"),
        "{}",
        stderr(&clash)
    );
    std::fs::remove_dir(project.join("@lib")).unwrap();

    let found = ms(&project, &cache, &["search_symbol", "greet"]);
    assert!(
        String::from_utf8_lossy(&found.stdout).contains("greet  fn"),
        "{found:?}"
    );

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
        "effects = [\"std.net.*\"]\n",
        include_str!("packages/greet.ms"),
    );
    app(
        &project,
        &format!("[dependencies]\n\"@lib\" = {}\n", table(&spec)),
    );
    let fetched = ms(&project, &cache, &["install"]);
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
        format!("\n[effects]\n\"@lib\" = [{allowed}]\n")
    };
    app(
        &project,
        &format!("[dependencies]\n\"@lib\" = {}\n{effects}", table(&spec)),
    );
    // A manifest `ms install` refuses is the result: there is nothing to check.
    let fetched = ms(&project, &cache, &["install"]);
    if !fetched.status.success() {
        return fetched;
    }
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
        "\"*\"",
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
        "effects = [\n    \"std.fs.read\", # a list may span lines\n]\n",
        include_str!("packages/reads.ms"),
        "\"std.fs.read\"",
    );
    assert!(declared.status.success(), "{}", stderr(&declared));
    // A space-separated string is no longer a list of effects.
    let string = checked_with(
        "package-string-effects",
        "effects = \"std.fs.read\"\n",
        include_str!("packages/reads.ms"),
        "\"std.fs.read\"",
    );
    assert!(!string.status.success());
    assert!(
        stderr(&string).contains("effects are a list of strings"),
        "{}",
        stderr(&string)
    );
}

#[test]
fn a_tampered_lock_never_reaches_git_and_nested_packages_must_use_https() {
    let root = scratch("package-lock-injection");
    let cache = root.join("cache");
    let (lib, project) = (root.join("lib"), root.join("app"));
    let spec = package(&lib, "", include_str!("packages/greet.ms"));
    app(
        &project,
        &format!("[dependencies]\n\"@lib\" = {}\n", table(&spec)),
    );
    let hash = "0".repeat(64);
    let lock = format!("\"@lib\" = \"{spec} --upload-pack=touch_pwned sha256:{hash}\"\n");
    std::fs::write(project.join("ms.lock"), lock).unwrap();
    let fetched = ms(&project, &cache, &["install"]);
    assert!(!fetched.status.success());
    assert!(stderr(&fetched).contains("ms.lock"), "{}", stderr(&fetched));
    assert!(!project.join("touch_pwned").exists() && !root.join("touch_pwned").exists());

    // A package's own dependencies may not read the local machine.
    let (outer, nested_app) = (root.join("outer"), root.join("nested-app"));
    let nested = format!("[dependencies]\n\"@inner\" = {}\n", table(&spec));
    let outer_spec = package(&outer, &nested, include_str!("packages/greet.ms"));
    app(
        &nested_app,
        &format!("[dependencies]\n\"@lib\" = {}\n", table(&outer_spec)),
    );
    let fetched = ms(&nested_app, &cache, &["install"]);
    assert!(!fetched.status.success());
    assert!(
        stderr(&fetched).contains("https://"),
        "{}",
        stderr(&fetched)
    );
}

#[test]
fn two_versions_of_one_package_are_named_when_their_types_meet() {
    let dir = scratch("packages-versions");
    let cache = dir.join("cache");
    let core = dir.join("core");
    let old = package(&core, "", include_str!("packages/id_v1.ms"));
    std::fs::write(core.join("src/lib.ms"), include_str!("packages/id_v2.ms")).unwrap();
    git(&core, &["commit", "-q", "-am", "second"]);
    git(&core, &["tag", "v2.0.0"]);
    let new = old.replace("#v1.0.0", "#v2.0.0");
    let project = dir.join("app");
    app(
        &project,
        &format!(
            "[dependencies]\n\"@old\" = {}\n\"@new\" = {}\n",
            table(&old),
            table(&new)
        ),
    );
    std::fs::write(
        project.join("src/main.ms"),
        include_str!("packages/two_versions.ms"),
    )
    .unwrap();
    let fetch = ms(&project, &cache, &["install"]);
    assert!(fetch.status.success(), "{}", stderr(&fetch));
    let check = ms(&project, &cache, &["check", "ms.toml"]);
    assert!(!check.status.success());
    let message = stderr(&check);
    assert!(
        message.contains("two versions of the package")
            && message.contains("@old at v1.0.0")
            && message.contains("@new at v2.0.0"),
        "{message}"
    );
}

/// `file:///C:/x` on Windows and `file:///x` elsewhere.
fn file_uri(path: &Path) -> String {
    let path = path.to_string_lossy().replace('\\', "/");
    let slash = if path.starts_with('/') { "" } else { "/" };
    format!("file://{slash}{path}")
}

/// Sends `requests` (id, method, params) to `ms lsp` after opening `file`, and returns the response to each.
fn lsp(
    project: &Path,
    cache: &Path,
    file: &Path,
    text: &str,
    requests: &[(u32, &str, String)],
) -> Vec<String> {
    use std::io::{BufRead, Read, Write};
    use std::process::Stdio;
    let uri = file_uri;
    let mut child = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("lsp")
        .env("MS_PACKAGE_CACHE", cache)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let mut stdout = std::io::BufReader::new(child.stdout.take().unwrap());
    let mut send = |body: String| {
        let framed = format!("Content-Length: {}\r\n\r\n{body}", body.len());
        stdin.write_all(framed.as_bytes()).unwrap();
        stdin.flush().unwrap();
    };
    let escaped = text
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n");
    send(format!(
        r#"{{"jsonrpc":"2.0","id":1,"method":"initialize","params":{{"rootUri":"{}","capabilities":{{}}}}}}"#,
        uri(project)
    ));
    send(r#"{"jsonrpc":"2.0","method":"initialized","params":{}}"#.into());
    send(format!(
        r#"{{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{{"textDocument":{{"uri":"{}","languageId":"manuscript","version":1,"text":"{escaped}"}}}}}}"#,
        uri(file)
    ));
    let mut read = || -> String {
        loop {
            let mut header = String::new();
            stdout.read_line(&mut header).unwrap();
            let length: usize = header
                .trim()
                .strip_prefix("Content-Length: ")
                .unwrap()
                .parse()
                .unwrap();
            stdout.read_line(&mut header).unwrap();
            let mut body = vec![0; length];
            stdout.read_exact(&mut body).unwrap();
            let body = String::from_utf8(body).unwrap();
            if body.contains("\"id\":") && !body.contains("\"method\"") {
                return body;
            }
        }
    };
    let _ = read();
    let mut answers = Vec::new();
    for (id, method, params) in requests {
        send(format!(
            r#"{{"jsonrpc":"2.0","id":{id},"method":"{method}","params":{params}}}"#
        ));
        answers.push(read());
    }
    send(r#"{"jsonrpc":"2.0","id":99,"method":"shutdown"}"#.into());
    send(r#"{"jsonrpc":"2.0","method":"exit"}"#.into());
    drop(stdin);
    let _ = child.wait();
    answers
}

#[test]
fn the_editor_follows_imports_into_a_package() {
    let dir = scratch("packages-editor");
    let cache = dir.join("cache");
    let url = package(&dir.join("lib"), "", include_str!("packages/greet.ms"));
    let project = dir.join("app");
    app(
        &project,
        &format!("[dependencies]\n\"@lib\" = {}\n", table(&url)),
    );
    let fetch = ms(&project, &cache, &["install"]);
    assert!(fetch.status.success(), "{}", stderr(&fetch));
    let main = project.join("src/main.ms");
    let text = include_str!("packages/main.ms");
    let uri = file_uri(&main);
    let at = |line: u32, character: u32| {
        format!(
            r#"{{"textDocument":{{"uri":"{uri}"}},"position":{{"line":{line},"character":{character}}}}}"#
        )
    };
    let answers = lsp(
        &project,
        &cache,
        &main,
        text,
        &[(2, "textDocument/definition", at(3, 12))],
    );
    // Definition lands in the cached copy of the package, which exists on disk.
    let stored = std::fs::read_dir(&cache)
        .unwrap()
        .flatten()
        .find(|e| e.path().join("src/lib.ms").is_file())
        .unwrap()
        .file_name()
        .to_string_lossy()
        .into_owned();
    assert!(
        answers[0].contains(&stored) && answers[0].contains("/src/lib.ms"),
        "{}",
        answers[0]
    );
    // Completion offers the dependency name, the package's files, and its exports.
    let names = lsp(
        &project,
        &cache,
        &main,
        "import greet from \"@\"\n",
        &[(2, "textDocument/completion", at(0, 20))],
    );
    assert!(names[0].contains("\"@lib/\""), "{}", names[0]);
    let files = lsp(
        &project,
        &cache,
        &main,
        "import greet from \"@lib/\"\n",
        &[(2, "textDocument/completion", at(0, 24))],
    );
    assert!(files[0].contains("@lib/lib.ms"), "{}", files[0]);
    let symbols = lsp(
        &project,
        &cache,
        &main,
        "import  from \"@lib/lib.ms\"\n",
        &[(2, "textDocument/completion", at(0, 7))],
    );
    assert!(symbols[0].contains("\"greet\""), "{}", symbols[0]);
}

#[test]
fn add_and_remove_edit_the_manifest_and_the_lock() {
    let dir = scratch("packages-add");
    let cache = dir.join("cache");
    let spec = package(
        &dir.join("lib"),
        "effects = [\"std.net.*\"]\n",
        include_str!("packages/greet_net.ms"),
    );
    let url = spec.trim_end_matches("#v1.0.0");
    let project = dir.join("app");
    app(&project, "");
    let manifest = |project: &Path| std::fs::read_to_string(project.join("ms.toml")).unwrap();

    // A tag that does not exist leaves the manifest as it was.
    let before = manifest(&project);
    let missing = ms(&project, &cache, &["add", url, "--tag", "v9.9.9"]);
    assert!(!missing.status.success());
    assert_eq!(manifest(&project), before);

    // Added without --allow: the package's effects are printed and the build refuses them.
    let added = ms(&project, &cache, &["add", url, "--tag", "v1.0.0"]);
    assert!(added.status.success(), "{}", stderr(&added));
    assert!(String::from_utf8_lossy(&added.stdout).contains("declares effects"));
    assert!(
        manifest(&project).contains("\"@lib\" = { url = "),
        "{}",
        manifest(&project)
    );
    assert!(project.join("ms.lock").is_file());
    assert!(!ms(&project, &cache, &["check", "ms.toml"]).status.success());
    let twice = ms(&project, &cache, &["add", url, "--tag", "v1.0.0"]);
    assert!(
        stderr(&twice).contains("already in [dependencies]"),
        "{}",
        stderr(&twice)
    );

    // Removing drops the dependency, and the lock with it.
    let removed = ms(&project, &cache, &["remove", "@lib"]);
    assert!(removed.status.success(), "{}", stderr(&removed));
    assert_eq!(manifest(&project).trim_end(), before.trim_end());
    assert!(!project.join("ms.lock").exists());
    let unknown = ms(&project, &cache, &["remove", "@lib"]);
    assert!(
        stderr(&unknown).contains("not in [dependencies]"),
        "{}",
        stderr(&unknown)
    );

    // --allow writes the effects, so the project builds.
    let allowed = ms(
        &project,
        &cache,
        &["add", url, "--sha", &sha_of(&dir.join("lib")), "--allow"],
    );
    assert!(allowed.status.success(), "{}", stderr(&allowed));
    assert!(
        manifest(&project).contains("\"@lib\" = [\"std.net.*\"]"),
        "{}",
        manifest(&project)
    );
    let checked = ms(&project, &cache, &["check", "ms.toml"]);
    assert!(checked.status.success(), "{}", stderr(&checked));
}

/// The commit `HEAD` names in the repository at `dir`.
fn sha_of(dir: &Path) -> String {
    let output = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .current_dir(dir)
        .output()
        .unwrap();
    String::from_utf8(output.stdout).unwrap().trim().to_string()
}
