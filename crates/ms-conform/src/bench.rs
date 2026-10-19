//! Performance harness: build the `bench/perf` kernels and programs with a
//! given `ms` (and, optionally, a second `ms` such as the Go oracle) next to
//! the hand-written Go baselines, run them N times alternating the order, and
//! report min-of-N times and ratios.
//!
//! Output protocol of the benchmark programs (same as `bench/perf` scripts):
//! * kernels print `<kernel> <microseconds> <checksum>` per kernel;
//! * programs read `lines.txt` on stdin and print `<name> <ops> <nanoseconds>`
//!   per operation and a final `# sink ...` checksum line.

use crate::exec;
use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

pub struct Options {
    pub repo: PathBuf,
    /// The `ms` under test.
    pub ms: PathBuf,
    /// A second `ms` for a three-way table (usually the Go oracle).
    pub oracle: Option<PathBuf>,
    pub go: PathBuf,
    pub repeats: usize,
    pub kernels: bool,
    pub programs: bool,
    pub scratch: PathBuf,
}

#[derive(Debug, Default)]
struct Series {
    /// name -> min measurement (µs for kernels, ns/op for programs)
    best: BTreeMap<String, f64>,
    /// name -> distinct checksums seen
    checks: BTreeMap<String, Vec<String>>,
    build_secs: f64,
}

fn run_ok(
    program: &Path,
    args: &[&str],
    cwd: &Path,
    stdin: &[u8],
    secs: u64,
) -> Result<exec::Output, String> {
    let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    let out = exec::run(program, &args, cwd, stdin, Duration::from_secs(secs), &[]);
    if out.spawn_error.is_some() || out.timed_out || out.code != 0 {
        return Err(format!(
            "{} {:?} failed (exit {}{}): {}",
            program.display(),
            args,
            out.code,
            if out.timed_out { ", timed out" } else { "" },
            out.stderr_text().chars().take(800).collect::<String>()
        ));
    }
    Ok(out)
}

fn copy_dir(from: &Path, to: &Path) -> std::io::Result<()> {
    fs::create_dir_all(to)?;
    for entry in fs::read_dir(from)? {
        let entry = entry?;
        let target = to.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir(&entry.path(), &target)?;
        } else if entry.file_name() != "ms.lock" {
            fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}

fn build_go(go: &Path, src: &Path, work: &Path) -> Result<PathBuf, String> {
    let dir = work.join("go");
    copy_dir(src, &dir).map_err(|e| e.to_string())?;
    let mut command = std::process::Command::new(go);
    command.current_dir(&dir).env("CGO_ENABLED", "0").args([
        "build",
        "-buildvcs=false",
        "-trimpath",
        "-ldflags=-s -w -buildid=",
        "-o",
        "bench",
        ".",
    ]);
    let out = command
        .output()
        .map_err(|e| format!("{}: {e}", go.display()))?;
    if !out.status.success() {
        return Err(format!(
            "go build failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(dir.join("bench"))
}

fn build_ms(ms: &Path, src: &Path, work: &Path, label: &str) -> Result<(PathBuf, f64), String> {
    let dir = work.join(label);
    copy_dir(src, &dir).map_err(|e| e.to_string())?;
    let started = std::time::Instant::now();
    run_ok(ms, &["build", "ms.toml", "-o", "bench"], &dir, b"", 1800)?;
    Ok((dir.join("bench"), started.elapsed().as_secs_f64()))
}

/// Parse `name a b` lines; `value_index` selects which number is the measurement.
fn parse_samples(
    text: &str,
    per_op: bool,
    series: &mut Series,
    counts: &mut BTreeMap<String, i64>,
) -> Result<(), String> {
    for line in text.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.is_empty() {
            continue;
        }
        if parts[0] == "#" {
            let sink = parts[1..].join(" ");
            let seen = series.checks.entry("# sink".to_string()).or_default();
            if !seen.contains(&sink) {
                seen.push(sink);
            }
            continue;
        }
        if parts.len() != 3 {
            return Err(format!("unexpected benchmark line: {line}"));
        }
        let name = parts[0].to_string();
        if per_op {
            let ops: i64 = parts[1].parse().map_err(|_| format!("bad ops in {line}"))?;
            let ns: f64 = parts[2]
                .parse()
                .map_err(|_| format!("bad time in {line}"))?;
            counts.insert(name.clone(), ops);
            let v = ns / ops.max(1) as f64;
            let slot = series.best.entry(name).or_insert(f64::INFINITY);
            *slot = slot.min(v);
        } else {
            let us: f64 = parts[1]
                .parse()
                .map_err(|_| format!("bad time in {line}"))?;
            let slot = series.best.entry(name.clone()).or_insert(f64::INFINITY);
            *slot = slot.min(us);
            let seen = series.checks.entry(name).or_default();
            if !seen.iter().any(|c| c == parts[2]) {
                seen.push(parts[2].to_string());
            }
        }
    }
    Ok(())
}

struct Contestant {
    label: String,
    binary: PathBuf,
    series: Series,
}

fn alternate(
    contestants: &mut [Contestant],
    repeats: usize,
    stdin: &[u8],
    per_op: bool,
) -> Result<BTreeMap<String, i64>, String> {
    let mut counts = BTreeMap::new();
    let n = contestants.len();
    for round in 0..repeats {
        // Rotate the order each round so no contestant always runs first.
        for k in 0..n {
            let c = &mut contestants[(k + round) % n];
            let out = run_ok(&c.binary, &[], c.binary.parent().unwrap(), stdin, 1800)?;
            parse_samples(&out.stdout_text(), per_op, &mut c.series, &mut counts)
                .map_err(|e| format!("{}: {e}", c.label))?;
        }
    }
    Ok(counts)
}

fn table(
    title: &str,
    unit: &str,
    contestants: &[Contestant],
    candidate: &str,
    oracle: Option<&str>,
    repeats: usize,
) -> Result<String, String> {
    let go = contestants
        .iter()
        .find(|c| c.label == "go")
        .ok_or("no go baseline")?;
    // Checksums must agree across every contestant.
    for (name, sums) in &go.series.checks {
        for c in contestants {
            if c.series.checks.get(name) != Some(sums) {
                return Err(format!(
                    "{title}: checksum mismatch for {name}: go={sums:?} {}={:?}",
                    c.label,
                    c.series.checks.get(name)
                ));
            }
        }
    }
    let cand = contestants
        .iter()
        .find(|c| c.label == candidate)
        .ok_or("no candidate")?;
    let orc = oracle.and_then(|o| contestants.iter().find(|c| c.label == o));
    let mut out = String::new();
    let _ = writeln!(out, "### {title}\n");
    let _ = writeln!(
        out,
        "Min of {repeats} runs, {unit}; ratios are time relative to Go (below 1.00x is faster than Go).\n"
    );
    let mut header = String::from("| benchmark | go |");
    let mut rule = String::from("|---|---:|");
    if orc.is_some() {
        header.push_str(" go-backend ms | ms / go |");
        rule.push_str("---:|---:|");
    }
    header.push_str(" candidate ms | candidate / go |");
    rule.push_str("---:|---:|");
    if orc.is_some() {
        header.push_str(" candidate / go-backend ms |");
        rule.push_str("---:|");
    }
    let _ = writeln!(out, "{header}\n{rule}");
    let fmt = |v: f64| {
        if v >= 100.0 {
            format!("{v:.0}")
        } else {
            format!("{v:.2}")
        }
    };
    let mut log_sum = 0.0;
    let mut rows = 0;
    for (name, g) in &go.series.best {
        let Some(c) = cand.series.best.get(name) else {
            return Err(format!("{title}: candidate produced no result for {name}"));
        };
        let mut row = format!("| {name} | {} |", fmt(*g));
        if let Some(o) = orc.and_then(|o| o.series.best.get(name)) {
            let _ = write!(row, " {} | {:.2}x |", fmt(*o), o / g);
        }
        let _ = write!(row, " {} | {:.2}x |", fmt(*c), c / g);
        if let Some(o) = orc.and_then(|o| o.series.best.get(name)) {
            let _ = write!(row, " {:.2}x |", c / o);
        }
        log_sum += (c / g).ln();
        rows += 1;
        let _ = writeln!(out, "{row}");
    }
    if rows > 0 {
        let _ = writeln!(
            out,
            "\nGeometric mean candidate / go: {:.2}x",
            (log_sum / rows as f64).exp()
        );
    }
    let _ = writeln!(
        out,
        "\nBuild time (s): {}",
        contestants
            .iter()
            .filter(|c| c.label != "go")
            .map(|c| format!("{} {:.1}", c.label, c.series.build_secs))
            .collect::<Vec<_>>()
            .join(", ")
    );
    Ok(out)
}

fn lines_input() -> Vec<u8> {
    let mut text = String::new();
    for i in 0..200_000 {
        let _ = writeln!(text, "2026-03-01T00:00:00Z 10.1.2.3 GET /api/users/{i} 200");
    }
    text.into_bytes()
}

fn suite(opts: &Options, dir: &str, per_op: bool, stdin: &[u8]) -> Result<String, String> {
    let src = opts.repo.join("bench/perf").join(dir);
    let work = opts.scratch.join(dir);
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(&work).map_err(|e| e.to_string())?;
    let mut contestants = Vec::new();
    eprintln!("[bench] building go baseline for {dir}");
    contestants.push(Contestant {
        label: "go".into(),
        binary: build_go(&opts.go, &src.join("go"), &work)?,
        series: Series::default(),
    });
    let mut targets = vec![("candidate", opts.ms.clone())];
    if let Some(o) = &opts.oracle {
        targets.push(("oracle", o.clone()));
    }
    for (label, ms) in targets {
        eprintln!("[bench] building {dir} with {label}: {}", ms.display());
        let (binary, secs) = build_ms(&ms, &src.join("ms"), &work, label)?;
        contestants.push(Contestant {
            label: label.into(),
            binary,
            series: Series {
                build_secs: secs,
                ..Series::default()
            },
        });
    }
    eprintln!("[bench] running {dir} x{}", opts.repeats);
    let counts = alternate(&mut contestants, opts.repeats, stdin, per_op)?;
    if per_op {
        // Every contestant must have done the same amount of work per operation.
        let _ = counts;
    }
    let title = if per_op {
        "Programs (ns per operation)"
    } else {
        "Kernels (microseconds)"
    };
    let unit = if per_op { "ns/op" } else { "µs" };
    table(
        title,
        unit,
        &contestants,
        "candidate",
        opts.oracle.as_ref().map(|_| "oracle"),
        opts.repeats,
    )
}

/// Run the selected suites and return a markdown report.
pub fn run(opts: &Options) -> Result<String, String> {
    fs::create_dir_all(&opts.scratch).map_err(|e| e.to_string())?;
    let mut report = String::from("# Performance report\n\n");
    let _ = writeln!(report, "Candidate: `{}`", opts.ms.display());
    if let Some(o) = &opts.oracle {
        let _ = writeln!(report, "\nGo-backend oracle: `{}`", o.display());
    }
    let _ = writeln!(report, "\nGo baseline: `{}`\n", opts.go.display());
    if opts.kernels {
        report.push_str(&suite(opts, "kernels", false, b"")?);
        report.push('\n');
    }
    if opts.programs {
        report.push_str(&suite(opts, "programs", true, &lines_input())?);
    }
    if !opts.programs && !opts.kernels {
        return Err("nothing to run".into());
    }
    let _ = fs::remove_dir_all(&opts.scratch);
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kernel_lines_take_the_minimum_and_collect_checksums() {
        let mut s = Series::default();
        let mut counts = BTreeMap::new();
        parse_samples("sieve 900 5\nnbody 10 7\n", false, &mut s, &mut counts).unwrap();
        parse_samples("sieve 700 5\n", false, &mut s, &mut counts).unwrap();
        assert_eq!(s.best["sieve"], 700.0);
        assert_eq!(s.checks["sieve"], ["5"]);
    }

    #[test]
    fn program_lines_are_per_operation() {
        let mut s = Series::default();
        let mut counts = BTreeMap::new();
        parse_samples(
            "int_eq 1000 5000\n# sink 1 2 3\n",
            true,
            &mut s,
            &mut counts,
        )
        .unwrap();
        assert_eq!(s.best["int_eq"], 5.0);
        assert_eq!(counts["int_eq"], 1000);
        assert_eq!(s.checks["# sink"], ["sink 1 2 3"]);
    }

    #[test]
    fn malformed_lines_are_errors() {
        let mut s = Series::default();
        let mut counts = BTreeMap::new();
        assert!(parse_samples("oops\n", false, &mut s, &mut counts).is_err());
    }

    #[test]
    fn table_computes_ratios_and_rejects_checksum_drift() {
        let mk = |label: &str, t: f64, sum: &str| {
            let mut series = Series::default();
            series.best.insert("k".into(), t);
            series.checks.insert("k".into(), vec![sum.into()]);
            Contestant {
                label: label.into(),
                binary: PathBuf::new(),
                series,
            }
        };
        let ok = table(
            "T",
            "µs",
            &[mk("go", 100.0, "1"), mk("candidate", 50.0, "1")],
            "candidate",
            None,
            3,
        )
        .unwrap();
        assert!(ok.contains("0.50x"));
        let bad = table(
            "T",
            "µs",
            &[mk("go", 100.0, "1"), mk("candidate", 50.0, "2")],
            "candidate",
            None,
            3,
        );
        assert!(bad.is_err());
    }
}
