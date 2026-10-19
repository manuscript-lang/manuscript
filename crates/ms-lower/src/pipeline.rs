//! Source file to native executable.

use crate::load;
use ms_mir::opt::{self, Level};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Pipeline options.
#[derive(Clone, Debug, Default)]
pub struct BuildOptions {
    /// Skip the MIR optimizer.
    pub no_opt: bool,
    /// Print MIR text to stderr.
    pub dump_mir: bool,
    /// Let the optimizer inline calls. Inlined callees lose their fault-trace frame, so the
    /// default keeps every source function.
    pub inline: bool,
}

/// Failure of a stage; `Diagnostics` were already printed.
#[derive(Debug)]
pub enum BuildError {
    /// The program has checker diagnostics.
    Diagnostics,
    /// Lowering or code generation failed.
    Failed(String),
}

fn runtime_library() -> Result<PathBuf, String> {
    if let Ok(p) = std::env::var("MSRT_LIB") {
        return Ok(PathBuf::from(p));
    }
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let dir = exe.parent().ok_or("no executable directory")?;
    for name in ["libms_native.a", "libms_rt.a"] {
        for d in [dir, dir.parent().unwrap_or(dir)] {
            let p = d.join(name);
            if p.exists() {
                return Ok(p);
            }
        }
    }
    Err("libms_native.a not found; build `cargo build -p ms-native` or set MSRT_LIB".to_string())
}

/// Which entry the executable gets.
enum Entry {
    /// The module's `main`.
    Main,
    /// A runner over the module's tests; the first argument is a test index.
    Tests,
}

fn build_entry(
    source: &Path,
    out: &Path,
    options: &BuildOptions,
    entry: Entry,
) -> Result<Vec<String>, BuildError> {
    let loaded = load::load(source);
    if !loaded.diagnostics.is_empty() {
        for d in &loaded.diagnostics {
            eprintln!("{d}");
        }
        return Err(BuildError::Diagnostics);
    }
    let program = loaded
        .program
        .ok_or_else(|| BuildError::Failed("no program".to_string()))?;
    let opts = crate::Options {
        entry: loaded.entry.clone(),
    };
    let lowered = match entry {
        Entry::Main => crate::lower_program(&program, &opts).map(|m| (m, Vec::new())),
        Entry::Tests => crate::lower_tests(&program, &opts),
    };
    let (mut m, names) = lowered.map_err(|e| BuildError::Failed(format!("lowering: {e}")))?;
    if let Err(errs) = ms_mir::verify::verify_module(&m) {
        let text = errs
            .iter()
            .take(8)
            .map(|e| e.to_string())
            .collect::<Vec<_>>()
            .join("\n");
        if options.dump_mir {
            eprintln!("{}", ms_mir::print::print_module(&m));
        }
        return Err(BuildError::Failed(format!(
            "MIR verification failed:\n{text}"
        )));
    }
    if !options.inline {
        for f in &mut m.funcs {
            f.inline = ms_mir::ir::InlineHint::Never;
        }
    }
    if !options.no_opt {
        opt::optimize(&mut m, Level::Speed, true);
    }
    if options.dump_mir {
        eprintln!("{}", ms_mir::print::print_module(&m));
    }
    let obj = ms_clif::compile(&m, &ms_clif::Options::default())
        .map_err(|e| BuildError::Failed(format!("codegen: {e}")))?;
    let objp = out.with_extension("o");
    std::fs::write(&objp, obj).map_err(|e| BuildError::Failed(e.to_string()))?;
    let rt = runtime_library().map_err(BuildError::Failed)?;
    ms_clif::link::link(&objp, &rt, out).map_err(|e| BuildError::Failed(e.to_string()))?;
    let _ = std::fs::remove_file(&objp);
    Ok(names)
}

/// Checks, lowers and compiles `source` into the executable `out`.
pub fn build(source: &Path, out: &Path, options: &BuildOptions) -> Result<(), BuildError> {
    build_entry(source, out, options, Entry::Main).map(|_| ())
}

/// Builds into a temporary directory and runs; returns the program's exit status.
pub fn run(source: &Path, args: &[String], options: &BuildOptions) -> Result<i32, BuildError> {
    let dir = std::env::temp_dir().join(format!("msl-{}", std::process::id()));
    std::fs::create_dir_all(&dir).map_err(|e| BuildError::Failed(e.to_string()))?;
    let exe = dir.join("program");
    let built = build(source, &exe, options);
    let result = built.and_then(|()| {
        let status = Command::new(&exe)
            .args(args)
            .status()
            .map_err(|e| BuildError::Failed(e.to_string()))?;
        Ok(status.code().unwrap_or(1))
    });
    let _ = std::fs::remove_dir_all(&dir);
    result
}

fn json_string(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// What one test process produced.
struct Ran {
    stdout: Vec<u8>,
    stderr: Vec<u8>,
    status: std::process::ExitStatus,
    timed_out: bool,
}

/// How long one test may run: `MSL_TEST_TIMEOUT` seconds (default 60, 0 for no limit).
fn test_timeout() -> Option<std::time::Duration> {
    let secs = std::env::var("MSL_TEST_TIMEOUT")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(60);
    (secs > 0).then(|| std::time::Duration::from_secs(secs))
}

/// Runs test `index` of `exe`, killing it when it outlives `limit`.
fn run_with_timeout(
    exe: &Path,
    index: usize,
    limit: Option<std::time::Duration>,
) -> std::io::Result<Ran> {
    use std::io::Read;
    use std::process::Stdio;
    let mut child = Command::new(exe)
        .arg(index.to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    fn drain<R: Read + Send + 'static>(mut r: R) -> std::thread::JoinHandle<Vec<u8>> {
        std::thread::spawn(move || {
            let mut buf = Vec::new();
            let _ = r.read_to_end(&mut buf);
            buf
        })
    }
    let out = drain(child.stdout.take().expect("piped stdout"));
    let err = drain(child.stderr.take().expect("piped stderr"));
    let start = std::time::Instant::now();
    let mut timed_out = false;
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if limit.is_some_and(|l| start.elapsed() >= l) {
            timed_out = true;
            child.kill()?;
            break child.wait()?;
        }
        std::thread::sleep(std::time::Duration::from_millis(5));
    };
    Ok(Ran {
        stdout: out.join().unwrap_or_default(),
        stderr: err.join().unwrap_or_default(),
        status,
        timed_out,
    })
}

/// The result of one test.
struct Outcome {
    name: String,
    failure: Option<String>,
    nanos: u128,
}

/// Builds the tests of `source`, runs each in its own process and reports like `ms test`.
/// With `json` the report is the machine-readable form; returns the exit status.
pub fn test(source: &Path, json: bool, options: &BuildOptions) -> Result<i32, BuildError> {
    let dir = std::env::temp_dir().join(format!("msl-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).map_err(|e| BuildError::Failed(e.to_string()))?;
    let exe = dir.join("tests");
    let result = build_entry(source, &exe, options, Entry::Tests).and_then(|names| {
        let file = source
            .file_name()
            .map(|f| f.to_string_lossy().into_owned())
            .unwrap_or_default();
        let mut stdout = String::new();
        let mut outcomes = Vec::new();
        for (i, name) in names.iter().enumerate() {
            let full = format!("{file}::{name}");
            stdout.push_str(&format!("RUN {full}\n"));
            let start = std::time::Instant::now();
            let out = run_with_timeout(&exe, i, test_timeout())
                .map_err(|e| BuildError::Failed(e.to_string()))?;
            let nanos = start.elapsed().as_nanos();
            stdout.push_str(&String::from_utf8_lossy(&out.stdout));
            let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
            let failure = if out.timed_out {
                Some(format!(
                    "timed out after {}s; the test was cancelled (MSL_TEST_TIMEOUT sets the limit in seconds, 0 disables it)",
                    test_timeout().map_or(0, |t| t.as_secs())
                ))
            } else if let Some(rest) = stderr.split_once(crate::FAILURE_MARKER) {
                Some(rest.1.to_string())
            } else if out.status.success() {
                None
            } else {
                Some(stderr.trim_end_matches('\n').to_string())
            };
            match &failure {
                None => stdout.push_str(&format!("PASS {full}\n")),
                Some(f) => stdout.push_str(&format!("FAIL {full}: {f}\n")),
            }
            outcomes.push(Outcome {
                name: full,
                failure,
                nanos,
            });
        }
        let failed = outcomes.iter().filter(|o| o.failure.is_some()).count();
        stdout.push_str(&format!("{} tests, {failed} failed\n", outcomes.len()));
        let code = i32::from(failed > 0);
        if !json {
            print!("{stdout}");
            return Ok(code);
        }
        let root = source
            .canonicalize()
            .ok()
            .and_then(|p| p.parent().map(|d| d.to_path_buf()))
            .unwrap_or_default();
        let tests: Vec<String> = outcomes
            .iter()
            .enumerate()
            .map(|(i, o)| {
                let status = if o.failure.is_some() { "failed" } else { "passed" };
                let failure = o
                    .failure
                    .as_ref()
                    .map(|f| format!(",\"failure\":{}", json_string(f)))
                    .unwrap_or_default();
                format!(
                    "{{\"index\":{i},\"duration_ns\":{},\"name\":{},\"status\":\"{status}\"{failure}}}",
                    o.nanos,
                    json_string(&o.name)
                )
            })
            .collect();
        let n = outcomes.len();
        println!(
            "{{\"repeat\":1,\"format\":1,\"source_root\":{},\"tests\":[{}],\"summary\":{{\"available\":{n},\"selected\":{n},\"passed\":{},\"failed\":{failed},\"skipped\":0,\"not_run\":0,\"duration_ns\":{}}},\"completed\":true,\"exit_code\":{code},\"stdout\":{},\"diagnostics\":[]}}",
            json_string(&root.to_string_lossy()),
            tests.join(","),
            n - failed,
            outcomes.iter().map(|o| o.nanos).sum::<u128>(),
            json_string(&stdout)
        );
        Ok(code)
    });
    if std::env::var_os("MSL_KEEP").is_none() {
        let _ = std::fs::remove_dir_all(&dir);
    }
    result
}
