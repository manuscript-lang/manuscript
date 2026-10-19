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
    for d in [dir, dir.parent().unwrap_or(dir)] {
        let p = d.join("libms_rt.a");
        if p.exists() {
            return Ok(p);
        }
    }
    Err("libms_rt.a not found; build `cargo build -p ms-rt` or set MSRT_LIB".to_string())
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
            let out = Command::new(&exe)
                .arg(i.to_string())
                .output()
                .map_err(|e| BuildError::Failed(e.to_string()))?;
            let nanos = start.elapsed().as_nanos();
            stdout.push_str(&String::from_utf8_lossy(&out.stdout));
            let stderr = String::from_utf8_lossy(&out.stderr).into_owned();
            let failure = if let Some(rest) = stderr.split_once(crate::FAILURE_MARKER) {
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
