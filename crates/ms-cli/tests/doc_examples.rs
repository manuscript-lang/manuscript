//! Tutorial fences marked `manuscript-example` must still compile and pass.
//!
//! `test` examples run under `ms test`. `run` examples are type-checked, and
//! executed with their arguments, input, file fixtures, local HTTP responses,
//! expected output and exit status. Every case gets an isolated working directory.
//! `reject` checks intentionally invalid full programs against diagnostic causes;
//! reference-only declarations use `check`. `filename` controls displayed test names.

use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use ms_json::Json;

const MARKER: &str = "<!-- manuscript-example: ";
const ARTIFACT_MARKER: &str = "<!-- manuscript-artifact: ";
const QUICKSTART_CHECK: &str = "Checked ms.toml (2 modules)\n";
const QUICKSTART_TEST: &str =
    "RUN test.ms::arithmetic\nPASS test.ms::arithmetic\n1 tests, 0 failed\n";

struct Fence {
    line: usize,
    language: String,
    source: String,
    example: Option<Json>,
    artifact: Option<Json>,
}

fn document_fences(file: &Path) -> Vec<Fence> {
    let markdown = fs::read_to_string(file).unwrap();
    let lines: Vec<_> = markdown.lines().collect();
    let mut fences = Vec::new();
    let mut index = 0;
    while index < lines.len() {
        let Some(info) = lines[index].strip_prefix("```") else {
            index += 1;
            continue;
        };
        let start = index;
        let annotation = |marker: &str| {
            lines
                .get(start.wrapping_sub(1))
                .and_then(|line| line.strip_prefix(marker))
                .map(|spec| {
                    ms_json::parse(spec.trim_end().trim_end_matches("-->").trim())
                        .unwrap_or_else(|error| panic!("{}:{}: {error}", file.display(), start))
                })
        };
        index += 1;
        let mut body = Vec::new();
        while index < lines.len() && !lines[index].starts_with("```") {
            body.push(lines[index]);
            index += 1;
        }
        assert!(
            index < lines.len(),
            "{}:{}: unclosed fence",
            file.display(),
            start + 1
        );
        fences.push(Fence {
            line: start + 1,
            language: info.split_whitespace().next().unwrap_or("").to_string(),
            source: body.join("\n") + "\n",
            example: annotation(MARKER),
            artifact: annotation(ARTIFACT_MARKER),
        });
        index += 1;
    }
    fences
}

fn variants(spec: &Json) -> Vec<&Json> {
    let mut variants = vec![spec];
    variants.extend(spec.get("cases").and_then(Json::as_array).unwrap_or(&[]));
    variants
}

fn stdout_expectations(spec: &Json) -> Vec<&str> {
    let mut expectations = Vec::new();
    for variant in variants(spec) {
        expectations.extend(text(variant, "stdout"));
        if let Some(Json::Obj(platforms)) = variant.get("stdout_by_os") {
            assert!(
                platforms.iter().any(|(os, _)| os == "default"),
                "stdout_by_os needs a default"
            );
            for (os, output) in platforms {
                assert!(
                    ["default", "windows", "linux", "macos"].contains(&os.as_str()),
                    "unknown stdout platform {os}"
                );
                expectations.push(output.as_str().expect("platform stdout must be a string"));
            }
        }
    }
    expectations
}

fn validate_document(file: &Path, fences: &[Fence]) {
    let mut preceding = Vec::new();
    let mut nearest = None;
    for fence in fences {
        let name = format!("{}:{}", file.display(), fence.line);
        if ["manuscript", "ms"].contains(&fence.language.as_str()) {
            assert!(
                fence.example.is_some() != fence.artifact.is_some(),
                "{name}: every Manuscript fence needs exactly one example or artifact annotation"
            );
            nearest = fence.example.as_ref();
            if let Some(spec) = &fence.example {
                preceding.push(spec);
                continue;
            }
            let spec = fence.artifact.as_ref().unwrap();
            let body: Vec<_> = fence
                .source
                .lines()
                .map(str::trim)
                .filter(|line| !line.is_empty() && !line.starts_with("//"))
                .collect();
            assert!(!body.is_empty(), "{name}: empty artifact");
            assert!(
                !body.iter().any(|line| line.starts_with("export fn main(")
                    || line.starts_with("fn main(")
                    || line.starts_with("test ")
                    || line.starts_with("bench ")),
                "{name}: executable programs need an example annotation"
            );
            match text(spec, "kind") {
                Some("schema") => {
                    assert!(
                        body.iter().any(|line| line.starts_with("interface ")
                            || line.starts_with("export type ")),
                        "{name}: schema must declare its API shape"
                    );
                    assert!(
                        !body.iter().any(|line| (line.starts_with("fn ")
                            || line.starts_with("var fn "))
                            && line.ends_with(':')),
                        "{name}: implemented functions are not API schemas"
                    );
                }
                Some("type-forms") => assert!(
                    body.iter().all(|line| line
                        .chars()
                        .all(|c| c.is_alphanumeric() || "_[]?, ".contains(c))),
                    "{name}: type forms cannot contain statements"
                ),
                Some("support") => {
                    let filename =
                        text(spec, "filename").expect("support artifact needs a filename");
                    let matched = fences
                        .iter()
                        .filter_map(|candidate| candidate.example.as_ref())
                        .any(|example| {
                            example
                                .get("build_files")
                                .and_then(|files| text(files, filename))
                                .is_some_and(|source| source.trim() == fence.source.trim())
                        });
                    assert!(
                        matched,
                        "{name}: support module must exactly match a consumer's build_files"
                    );
                }
                Some("import") => assert!(
                    body.iter().all(|line| line.starts_with("import ")),
                    "{name}: import reference must contain only imports"
                ),
                Some("edit") => assert!(
                    body.len() == 1 && body[0].starts_with("let "),
                    "{name}: edit artifact must be a single replacement binding"
                ),
                other => panic!("{name}: unknown artifact kind {other:?}"),
            }
        } else if fence.language == "text" {
            let first = fence.source.lines().next().unwrap_or("");
            let transcript = first.starts_with("RUN ")
                || first.starts_with("Checked ")
                || first.contains(".ms::");
            if !transcript {
                continue;
            }
            let project_transcript = (file.ends_with("learn/getting-started.md")
                && fence.source == format!("{QUICKSTART_CHECK}{QUICKSTART_TEST}"))
                || (file.ends_with("developer-tooling/builds/project-configuration.md")
                    && fence.source == QUICKSTART_CHECK)
                || (file.ends_with("developer-tooling/how-it-works.md")
                    && fence.source == format!("{QUICKSTART_CHECK}Arguments: 2\n"));
            if project_transcript {
                continue; // These exact init/run/check outputs are exercised by the project command regression below.
            }
            if let Some(spec) = nearest
                && matches!(text(spec, "mode"), Some("test" | "check"))
            {
                assert!(
                    !stdout_expectations(spec).is_empty(),
                    "{name}: visible transcript needs stdout metadata on its example"
                );
            }
            assert!(
                preceding
                    .iter()
                    .any(|spec| stdout_expectations(spec).contains(&fence.source.as_str())),
                "{name}: displayed transcript must match a preceding example's stdout or command/platform variant"
            );
        }
    }
}

struct Example {
    file: PathBuf,
    line: usize,
    spec: Json,
    source: String,
}

fn markdown_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            markdown_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "md") {
            out.push(path);
        }
    }
}

fn examples() -> Vec<Example> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../documentation");
    let mut files = Vec::new();
    markdown_files(&root, &mut files);
    files.sort();
    let mut found = Vec::new();
    for file in files {
        let fences = document_fences(&file);
        validate_document(&file, &fences);
        for fence in fences {
            if let Some(spec) = fence.example {
                found.push(Example {
                    file: file.clone(),
                    line: fence.line,
                    spec,
                    source: fence.source,
                });
            }
        }
    }
    found
}

fn text<'a>(spec: &'a Json, key: &str) -> Option<&'a str> {
    spec.get(key).and_then(Json::as_str)
}

fn fixture_path(dir: &Path, name: &str) -> PathBuf {
    assert!(
        Path::new(name)
            .components()
            .all(|part| matches!(part, std::path::Component::Normal(_))),
        "fixture paths must stay inside the example directory: {name}"
    );
    dir.join(name)
}

fn run(command: &mut Command, stdin: &str) -> std::process::Output {
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(stdin.as_bytes()).ok();
    child.wait_with_output().unwrap()
}

fn ms(dir: &Path, args: &[&str]) -> std::process::Output {
    run(
        Command::new(env!("CARGO_BIN_EXE_ms"))
            .current_dir(dir)
            .args(args),
        "",
    )
}

fn write_files(dir: &Path, spec: &Json, key: &str) {
    if let Some(Json::Obj(files)) = spec.get(key) {
        for (name, contents) in files {
            let path = fixture_path(dir, name);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(
                path,
                contents.as_str().expect("file contents must be strings"),
            )
            .unwrap();
        }
    }
}

fn check_output(spec: &Json, output: &std::process::Output) -> Result<(), String> {
    for (key, actual) in [("stdout", &output.stdout), ("stderr", &output.stderr)] {
        let want = text(spec, key).or_else(|| {
            let platforms = spec.get(&format!("{key}_by_os"))?;
            text(platforms, std::env::consts::OS).or_else(|| text(platforms, "default"))
        });
        if let Some(want) = want
            && actual != want.as_bytes()
        {
            return Err(format!(
                "expected {key} {want:?}, got {:?}",
                String::from_utf8_lossy(actual)
            ));
        }
    }
    Ok(())
}

fn run_case(source: &Path, dir: &Path, spec: &Json) -> Result<(), String> {
    fs::create_dir_all(dir).unwrap();
    write_files(dir, spec, "files");
    let mut url = String::new();
    let server = spec.get("http").map(|http| {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        url = format!("http://{}/", listener.local_addr().unwrap());
        listener.set_nonblocking(true).unwrap();
        let status = http.get("status").and_then(Json::as_i64).unwrap_or(200);
        let body = text(http, "body").unwrap_or("");
        let response = format!(
            "HTTP/1.1 {status} Example\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        std::thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(10);
            loop {
                match listener.accept() {
                    Ok((mut stream, _)) => {
                        stream
                            .set_read_timeout(Some(Duration::from_secs(5)))
                            .unwrap();
                        let mut request = Vec::new();
                        while !request.ends_with(b"\r\n\r\n") {
                            let mut byte = [0];
                            stream.read_exact(&mut byte).unwrap();
                            request.push(byte[0]);
                            assert!(request.len() <= 16384, "example request headers too large");
                        }
                        stream.write_all(response.as_bytes()).unwrap();
                        return;
                    }
                    Err(error)
                        if error.kind() == std::io::ErrorKind::WouldBlock
                            && Instant::now() < deadline =>
                    {
                        std::thread::sleep(Duration::from_millis(10));
                    }
                    Err(error) => panic!("example HTTP server did not receive a request: {error}"),
                }
            }
        })
    });
    let args: Vec<String> = spec
        .get("args")
        .and_then(Json::as_array)
        .unwrap_or(&[])
        .iter()
        .map(|arg| {
            arg.as_str()
                .expect("argument must be a string")
                .replace("$HTTP_URL", &url)
        })
        .collect();
    let output = run(
        Command::new(env!("CARGO_BIN_EXE_ms"))
            .current_dir(dir)
            .arg("run")
            .arg(source)
            .arg("--")
            .args(args),
        text(spec, "stdin").unwrap_or(""),
    );
    if let Some(server) = server {
        server.join().expect("example HTTP server failed");
    }
    let want_exit = spec.get("exit_code").and_then(Json::as_i64).unwrap_or(0) as i32;
    if output.status.code() != Some(want_exit) {
        return Err(format!(
            "expected exit {want_exit}, got {}\n{}",
            output.status,
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    check_output(spec, &output)?;
    if let Some(Json::Obj(files)) = spec.get("want_files") {
        for (name, want) in files {
            let actual = fs::read_to_string(fixture_path(dir, name))
                .map_err(|error| format!("{name}: {error}"))?;
            if Some(actual.as_str()) != want.as_str() {
                return Err(format!("{name}: expected {want:?}, got {actual:?}"));
            }
        }
    }
    Ok(())
}

#[test]
fn marked_tutorial_examples_compile_and_pass() {
    let dir = std::env::temp_dir().join(format!("ms-doc-examples-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let mut failures = Vec::new();
    let all = examples();
    assert!(all.len() >= 20, "found only {} examples", all.len());
    for (n, example) in all.iter().enumerate() {
        let example_dir = dir.join(format!("example{n}"));
        fs::create_dir_all(&example_dir).unwrap();
        let path = fixture_path(
            &example_dir,
            text(&example.spec, "filename").unwrap_or("example.ms"),
        );
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, &example.source).unwrap();
        write_files(&example_dir, &example.spec, "build_files");
        let absolute_path = path.clone();
        let path = path.strip_prefix(&example_dir).unwrap().to_str().unwrap();
        let name = format!("{}:{}", example.file.display(), example.line);
        let mode = text(&example.spec, "mode").expect("example needs a mode");
        let args = match mode {
            "test" => vec!["test", path],
            "bench" => vec!["bench", path, "--time", "5ms", "--samples", "2"],
            "check" | "reject" => vec!["check", path],
            "run" => vec!["check", path],
            other => panic!("{name}: unknown example mode {other}"),
        };
        let command_cases = if mode == "run" {
            vec![&example.spec]
        } else {
            variants(&example.spec)
        };
        for spec in command_cases {
            let mut invocation = args.clone();
            if mode != "run" {
                invocation.extend(
                    spec.get("args")
                        .and_then(Json::as_array)
                        .unwrap_or(&[])
                        .iter()
                        .map(|arg| arg.as_str().expect("command argument must be a string")),
                );
            }
            let output = ms(&example_dir, &invocation);
            if mode == "reject" {
                let expected = match spec.get("stderr_contains") {
                    Some(Json::Str(cause)) => vec![cause.as_str()],
                    Some(Json::Arr(causes)) => causes
                        .iter()
                        .map(|cause| cause.as_str().expect("diagnostic cause must be a string"))
                        .collect(),
                    _ => panic!("{name}: reject examples need stderr_contains diagnostic causes"),
                };
                assert!(
                    !expected.is_empty() && expected.iter().all(|cause| !cause.is_empty()),
                    "{name}: rejection needs a nonempty diagnostic cause"
                );
                let stderr = String::from_utf8_lossy(&output.stderr);
                if output.status.success() || expected.iter().any(|cause| !stderr.contains(cause)) {
                    failures.push(format!(
                        "{name}: expected rejection containing {expected:?}, got {}\n{stderr}",
                        output.status
                    ));
                }
                continue;
            }
            let expected_exit = if mode == "run" {
                0
            } else {
                spec.get("exit_code").and_then(Json::as_i64).unwrap_or(0) as i32
            };
            assert!(
                expected_exit == 0
                    || text(spec, "stdout").is_some()
                    || text(spec, "stderr").is_some(),
                "{name}: an expected failing command needs exact stdout or stderr"
            );
            if output.status.code() != Some(expected_exit) {
                failures.push(format!(
                    "{name}: ms {mode} expected exit {expected_exit}, got {}\n{}\n{}",
                    output.status,
                    String::from_utf8_lossy(&output.stdout),
                    String::from_utf8_lossy(&output.stderr)
                ));
                continue;
            }
            if mode != "run" {
                if let Err(error) = check_output(spec, &output) {
                    failures.push(format!("{name}: {error}"));
                }
                continue;
            }
        }
        if mode != "run" {
            continue;
        }
        let cases = variants(&example.spec);
        for (case, spec) in cases.into_iter().enumerate() {
            if let Err(error) = run_case(
                &absolute_path,
                &example_dir.join(format!("case{case}")),
                spec,
            ) {
                failures.push(format!("{name} case {case}: {error}"));
            }
        }
    }
    fs::remove_dir_all(&dir).ok();
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn getting_started_commands_produce_the_documented_program_and_code_map() {
    let dir = std::env::temp_dir().join(format!("ms-doc-getting-started-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let check = |cwd: &Path, args: &[&str], want: Option<&str>| {
        let output = ms(cwd, args);
        assert!(
            output.status.success(),
            "{args:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        if let Some(want) = want {
            assert_eq!(String::from_utf8_lossy(&output.stdout), want, "{args:?}");
        }
    };
    check(&dir, &["--version"], None);
    check(&dir, &["--help"], None);
    check(&dir, &["init", "my-app"], None);
    let project = dir.join("my-app");
    check(
        &project,
        &["run", "ms.toml", "--", "first", "second"],
        Some("Arguments: 2\n"),
    );
    let main = project.join("src/main.ms");
    let source = examples()
        .into_iter()
        .find(|example| example.file.ends_with("learn/getting-started.md"))
        .expect("getting-started must include its replacement main")
        .source;
    fs::write(&main, &source).unwrap();
    check(
        &project,
        &["run", "ms.toml", "--", "first", "second"],
        Some("Arguments: 2\n"),
    );
    let guide =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../documentation/learn/getting-started.md");
    let replacement = document_fences(&guide)
        .into_iter()
        .find(|fence| {
            fence
                .artifact
                .as_ref()
                .is_some_and(|spec| text(spec, "kind") == Some("edit"))
        })
        .expect("getting-started needs its edit instruction")
        .source;
    let original = source
        .lines()
        .find(|line| line.trim_start().starts_with("let message ="))
        .expect("main needs the message binding");
    fs::write(main, source.replace(original.trim(), replacement.trim())).unwrap();
    check(
        &project,
        &["run", "ms.toml", "--", "first", "second"],
        Some("Hello! You passed 2 arguments.\n"),
    );
    check(&project, &["check", "ms.toml"], Some(QUICKSTART_CHECK));
    check(&project, &["fmt", "ms.toml"], Some(""));
    check(&project, &["test", "ms.toml"], Some(QUICKSTART_TEST));
    check(&project, &["verify", "ms.toml"], None);
    let executable = project.join(if cfg!(windows) { "hello.exe" } else { "hello" });
    check(
        &project,
        &["build", "ms.toml", "-o", executable.to_str().unwrap()],
        None,
    );
    let output = run(
        Command::new(executable)
            .current_dir(&project)
            .args(["first", "second"]),
        "",
    );
    assert!(output.status.success());
    assert_eq!(output.stdout, b"Hello! You passed 2 arguments.\n");
    check(
        &project,
        &[
            "diagram",
            "ms.toml",
            "--format",
            "html",
            "-o",
            "code-map.html",
        ],
        Some(""),
    );
    let html = fs::read_to_string(project.join("code-map.html")).unwrap();
    assert!(html.contains("<html"));
    assert!(html.contains("Hello! You passed"));
    fs::remove_dir_all(dir).unwrap();
}
