//! Tutorial fences marked `manuscript-example` must still compile and pass.
//!
//! `test` examples run under `ms test`. `run` examples are type-checked, and
//! executed with their arguments, input, file fixtures, local HTTP responses,
//! expected output and exit status. Every case gets an isolated working directory.

use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use ms_json::Json;

const MARKER: &str = "<!-- manuscript-example: ";

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
        let text = fs::read_to_string(&file).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        for (i, line) in lines.iter().enumerate() {
            let Some(rest) = line.strip_prefix(MARKER) else {
                continue;
            };
            let spec = ms_json::parse(rest.trim_end().trim_end_matches("-->").trim())
                .unwrap_or_else(|err| panic!("{file:?}:{}: {err}", i + 1));
            let fence = lines.get(i + 1).copied().unwrap_or("");
            assert!(fence.starts_with("```manuscript"), "{file:?}:{}", i + 1);
            let body: Vec<&str> = lines[i + 2..]
                .iter()
                .copied()
                .take_while(|l| !l.starts_with("```"))
                .collect();
            found.push(Example {
                file: file.clone(),
                line: i + 1,
                spec,
                source: body.join("\n") + "\n",
            });
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

fn run_case(executable: &Path, dir: &Path, spec: &Json) -> Result<(), String> {
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
        Command::new(executable).current_dir(dir).args(args),
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
    for (key, actual) in [("stdout", &output.stdout), ("stderr", &output.stderr)] {
        if let Some(want) = text(spec, key)
            && actual != want.as_bytes()
        {
            return Err(format!(
                "expected {key} {want:?}, got {:?}",
                String::from_utf8_lossy(actual)
            ));
        }
    }
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
        let path = example_dir.join("example.ms");
        fs::write(&path, &example.source).unwrap();
        write_files(&example_dir, &example.spec, "build_files");
        let path = path.to_str().unwrap();
        let name = format!("{}:{}", example.file.display(), example.line);
        let mode = text(&example.spec, "mode").expect("example needs a mode");
        let executable = example_dir.join(if cfg!(windows) {
            "example.exe"
        } else {
            "example"
        });
        let args = match mode {
            "test" => vec!["test", path],
            "bench" => vec!["bench", path, "--time", "5ms", "--samples", "2"],
            "check" => vec!["check", path],
            "run" => vec!["build", path, "-o", executable.to_str().unwrap()],
            other => panic!("{name}: unknown example mode {other}"),
        };
        let output = ms(&example_dir, &args);
        if !output.status.success() {
            failures.push(format!(
                "{name}: ms {mode} failed\n{}\n{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            ));
            continue;
        }
        if mode != "run" {
            continue;
        }
        let mut cases = vec![&example.spec];
        cases.extend(
            example
                .spec
                .get("cases")
                .and_then(Json::as_array)
                .unwrap_or(&[]),
        );
        for (case, spec) in cases.into_iter().enumerate() {
            if let Err(error) =
                run_case(&executable, &example_dir.join(format!("case{case}")), spec)
            {
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
    check(&dir, &["init", "my-app"], None);
    let project = dir.join("my-app");
    check(
        &project,
        &["run", "ms.toml", "--", "first", "second"],
        Some("Arguments: 2\n"),
    );
    let main = project.join("src/main.ms");
    let source = fs::read_to_string(&main).unwrap();
    assert!(source.contains("Arguments: {arguments().length()}"));
    fs::write(
        main,
        source.replace(
            "Arguments: {arguments().length()}",
            "Hello! You passed {arguments().length()} arguments.",
        ),
    )
    .unwrap();
    check(
        &project,
        &["run", "ms.toml", "--", "first", "second"],
        Some("Hello! You passed 2 arguments.\n"),
    );
    check(
        &project,
        &["check", "ms.toml"],
        Some("Checked ms.toml (2 modules)\n"),
    );
    check(&project, &["fmt", "ms.toml"], Some(""));
    check(
        &project,
        &["test", "ms.toml"],
        Some("RUN test.ms::arithmetic\nPASS test.ms::arithmetic\n1 tests, 0 failed\n"),
    );
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
