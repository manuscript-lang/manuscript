use ms_conform::cli::Args;
use ms_conform::fixture::{self, Fixture, FixtureRoot, Meta, Phase};
use ms_conform::json::{self, Json};
use ms_conform::observe::Ctx;
use ms_conform::record::{self, RecordOpts};
use ms_conform::report;
use ms_conform::runner::{self, ExpectFail};
use ms_conform::{fuzz, harvest};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "\
ms-conform: conformance corpus runner for any `ms` binary

usage: ms-conform <command> [options]

commands:
  run       run the corpus against --ms and compare with the recorded expectations
  record    regenerate expectations from the binary given by --ms
  diff      run two binaries (--a, --b) on the corpus and compare them directly
  list      list fixtures (id, phase, tags)
  stats     count fixtures per phase and tag
  lint      validate fixture metadata and expectation files
  harvest   turn repository sources, and doc fences into fixtures
  retag     recompute tier-* tags on every fixture from its imports
  fuzz-gen  write deterministic generated fixtures into the corpus
  fuzz      differential fuzzing: generate programs, run --oracle and --ms, compare

selection (run, record, diff, list, stats):
  --corpus DIR        fixtures directory (default: tests/conformance/fixtures above the cwd)
  --tag T[,T]         only fixtures with any of these tags (repeatable)
  --exclude-tag T     skip fixtures with this tag
  --phase P[,P]       parse, check, run or test
  --id TEXT           only fixtures whose id contains TEXT
  --shard I/N         every Nth fixture starting at I (0-based) for parallel CI jobs
  --jobs N            parallel fixtures (default: half the cores)
  --timeout-scale F   multiply every timeout

run options:
  --ms PATH           binary under test (default: $MS, ./ms, or ms on PATH)
  --expect-fail FILE  allowlist of known failures (ids or prefix*); only others fail the run
  --write-expect-fail FILE   write the current failures as an allowlist
  --json FILE         machine-readable report
  --markdown FILE     markdown report (pass rate per tag and phase, failing fixtures with diffs)
  --max-failures N    failures shown in the markdown report (default 100)
  --strict            also fail on unexpected passes (allowlist entries that now pass)

record options:
  --no-stable-check   do not run each fixture twice to prove determinism
  --prune             delete fixtures that are unstable or cannot be recorded
  --only-missing      keep existing expectations

harvest options:    --ms PATH --repo DIR [--no-docs] [--no-tree] [--no-twins]
                    (then run `record --prune` to write expectations and drop unstable fixtures)
fuzz-gen options:   --kind run|type|syntax  --seeds A..B  [--corpus DIR]
fuzz options:       --oracle PATH --ms PATH --kind K --seeds A..B [--save DIR]
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some((command, rest)) = args.split_first() else {
        print!("{USAGE}");
        return ExitCode::from(2);
    };
    if matches!(command.as_str(), "help" | "--help" | "-h") {
        print!("{USAGE}");
        return ExitCode::SUCCESS;
    }
    let parsed = match Args::parse(rest) {
        Ok(a) => a,
        Err(e) => return fail(&e),
    };
    if parsed.has("help") {
        print!("{USAGE}");
        return ExitCode::SUCCESS;
    }
    let result = match command.as_str() {
        "run" => cmd_run(&parsed),
        "record" => cmd_record(&parsed),
        "diff" => cmd_diff(&parsed),
        "list" => cmd_list(&parsed),
        "stats" => cmd_stats(&parsed),
        "lint" => cmd_lint(&parsed),
        "harvest" => cmd_harvest(&parsed),
        "retag" => cmd_retag(&parsed),
        "fuzz-gen" => cmd_fuzz_gen(&parsed),
        "fuzz" => cmd_fuzz(&parsed),
        other => Err(format!("unknown command {other}; try --help")),
    };
    match result {
        Ok(code) => ExitCode::from(code),
        Err(e) => fail(&e),
    }
}

fn fail(message: &str) -> ExitCode {
    eprintln!("ms-conform: {message}");
    ExitCode::from(2)
}

fn context(args: &Args, flag: &str) -> Result<Ctx, String> {
    let mut ctx = Ctx::new(args.ms(flag));
    if let Some(scale) = args.number::<f64>("timeout-scale")? {
        ctx.timeout_scale = scale;
    }
    Ok(ctx)
}

fn load(args: &Args) -> Result<Vec<Fixture>, String> {
    let corpus = args.corpus()?;
    let (fixtures, warnings) = fixture::discover(&corpus);
    for w in warnings {
        eprintln!("warning: {w}");
    }
    if fixtures.is_empty() {
        return Err(format!("no fixtures under {}", corpus.display()));
    }
    Ok(fixtures)
}

fn write_file(path: &str, text: &str) -> Result<(), String> {
    if let Some(parent) = Path::new(path).parent() {
        let _ = fs::create_dir_all(parent);
    }
    fs::write(path, text).map_err(|e| format!("{path}: {e}"))
}

fn print_summary(cases: &[runner::Case]) {
    let s = report::summarize(cases);
    println!(
        "{} fixtures: {} pass, {} fail, {} expected fail, {} unexpected pass, {} unrecorded ({:.1}%)",
        s.all.total,
        s.all.pass,
        s.all.fail,
        s.all.expected_fail,
        s.all.unexpected_pass,
        s.all.unrecorded,
        s.all.rate()
    );
    for (p, t) in &s.by_phase {
        println!(
            "  {:<6} {:>5}/{:<5} {:.1}%",
            p.name(),
            t.passing(),
            t.total,
            t.rate()
        );
    }
    for c in cases
        .iter()
        .filter(|c| {
            matches!(
                c.outcome,
                runner::Outcome::Fail | runner::Outcome::Unrecorded
            )
        })
        .take(30)
    {
        println!("FAIL {}\n{}", c.id, indent(&c.diff));
    }
    let failing = cases
        .iter()
        .filter(|c| {
            matches!(
                c.outcome,
                runner::Outcome::Fail | runner::Outcome::Unrecorded
            )
        })
        .count();
    if failing > 30 {
        println!(
            "... {} more failures (see --markdown / --json)",
            failing - 30
        );
    }
}

fn indent(text: &str) -> String {
    text.lines().map(|l| format!("    {l}\n")).collect()
}

fn cmd_run(args: &Args) -> Result<u8, String> {
    let all = load(args)?;
    let filter = args.filter()?;
    let selected = runner::select(&all, &filter);
    let ctx = context(args, "ms")?;
    let allow = match args.one("expect-fail") {
        Some(p) => ExpectFail::load(Path::new(p))?,
        None => ExpectFail::default(),
    };
    eprintln!(
        "running {} of {} fixtures with {}",
        selected.len(),
        all.len(),
        ctx.ms.display()
    );
    let cases = runner::run_all(&ctx, &selected, &allow, args.jobs()?, !args.has("quiet"));
    print_summary(&cases);
    let ms = ctx.ms.display().to_string();
    if let Some(p) = args.one("json") {
        write_file(
            p,
            &report::to_json(&ms, &cases).pretty_line(ms_json::Escape::Plain),
        )?;
    }
    let max = args.number::<usize>("max-failures")?.unwrap_or(100);
    if let Some(p) = args.one("markdown") {
        write_file(p, &report::to_markdown(&ms, &cases, max))?;
    }
    if let Some(p) = args.one("write-expect-fail") {
        let mut text = String::from("# Known failures; remove entries as they are fixed.\n");
        for c in cases.iter().filter(|c| {
            !matches!(
                c.outcome,
                runner::Outcome::Pass | runner::Outcome::UnexpectedPass
            )
        }) {
            text.push_str(&c.id);
            text.push('\n');
        }
        write_file(p, &text)?;
    }
    let strict_fail = args.has("strict")
        && cases
            .iter()
            .any(|c| c.outcome == runner::Outcome::UnexpectedPass);
    Ok(u8::from(report::has_regressions(&cases) || strict_fail))
}

fn cmd_record(args: &Args) -> Result<u8, String> {
    let all = load(args)?;
    let filter = args.filter()?;
    let selected = runner::select(&all, &filter);
    let ctx = context(args, "ms")?;
    eprintln!(
        "recording {} fixtures from {}",
        selected.len(),
        ctx.ms.display()
    );
    let opts = RecordOpts {
        jobs: args.jobs()?,
        check_stable: !args.has("no-stable-check"),
        prune: args.has("prune"),
        only_missing: args.has("only-missing"),
    };
    let summary = record::record(&ctx, &selected, opts);
    println!(
        "{} written, {} unchanged, {} rejected",
        summary.written,
        summary.unchanged,
        summary.rejected.len()
    );
    for (id, reason) in &summary.rejected {
        println!(
            "REJECTED {id}{}\n{}",
            if opts.prune { " (deleted)" } else { "" },
            indent(reason)
        );
    }
    Ok(u8::from(!summary.rejected.is_empty()))
}

fn cmd_diff(args: &Args) -> Result<u8, String> {
    let all = load(args)?;
    let filter = args.filter()?;
    let selected = runner::select(&all, &filter);
    let a = context(args, "a")?;
    let mut b = context(args, "b")?;
    b.scratch = b.scratch.with_file_name(format!(
        "{}-b",
        b.scratch.file_name().unwrap_or_default().to_string_lossy()
    ));
    let cases = record::diff_binaries(&a, &b, &selected, args.jobs()?);
    print_summary(&cases);
    let label = format!("{} vs {}", a.ms.display(), b.ms.display());
    if let Some(p) = args.one("json") {
        write_file(
            p,
            &report::to_json(&label, &cases).pretty_line(ms_json::Escape::Plain),
        )?;
    }
    if let Some(p) = args.one("markdown") {
        let max = args.number::<usize>("max-failures")?.unwrap_or(100);
        write_file(p, &report::to_markdown(&label, &cases, max))?;
    }
    Ok(u8::from(report::has_regressions(&cases)))
}

fn cmd_list(args: &Args) -> Result<u8, String> {
    let all = load(args)?;
    for f in runner::select(&all, &args.filter()?) {
        println!("{}\t{}\t{}", f.id, f.phase.name(), f.tags.join(","));
    }
    Ok(0)
}

fn cmd_stats(args: &Args) -> Result<u8, String> {
    let all = load(args)?;
    let selected = runner::select(&all, &args.filter()?);
    let mut by_tag: BTreeMap<&str, BTreeMap<Phase, usize>> = BTreeMap::new();
    let mut by_phase: BTreeMap<Phase, usize> = BTreeMap::new();
    for f in &selected {
        *by_phase.entry(f.phase).or_default() += 1;
        for t in &f.tags {
            *by_tag.entry(t).or_default().entry(f.phase).or_default() += 1;
        }
    }
    println!("{} fixtures", selected.len());
    print!("| tag | total |");
    for p in Phase::ALL {
        print!(" {} |", p.name());
    }
    println!();
    println!("|---|---:|---:|---:|---:|---:|");
    print!("| all | {} |", selected.len());
    for p in Phase::ALL {
        print!(" {} |", by_phase.get(&p).copied().unwrap_or(0));
    }
    println!();
    for (tag, phases) in &by_tag {
        print!("| {tag} | {} |", phases.values().sum::<usize>());
        for p in Phase::ALL {
            print!(" {} |", phases.get(&p).copied().unwrap_or(0));
        }
        println!();
    }
    Ok(0)
}

fn cmd_lint(args: &Args) -> Result<u8, String> {
    let corpus = args.corpus()?;
    let (fixtures, warnings) = fixture::discover(&corpus);
    let mut problems: Vec<String> = warnings;
    let mut ids = std::collections::BTreeSet::new();
    let mut expected_files = std::collections::BTreeSet::new();
    for f in &fixtures {
        if !ids.insert(f.id.clone()) {
            problems.push(format!("{}: duplicate id", f.id));
        }
        if f.tags.is_empty() {
            problems.push(format!("{}: no tags", f.id));
        }
        for t in &f.tags {
            if !fixture::tag_allowed(t) {
                problems.push(format!("{}: unknown tag {t}", f.id));
            }
        }
        if f.phase == Phase::Parse && matches!(f.root, FixtureRoot::Dir(_)) {
            problems.push(format!("{}: parse fixtures must be single files", f.id));
        }
        expected_files.insert(f.expected_path.clone());
        match runner::load_expected(f) {
            Err(e) => problems.push(format!("{}: {e}", f.id)),
            Ok(_) => {
                let doc = fs::read_to_string(&f.expected_path)
                    .ok()
                    .and_then(|t| json::parse(&t).ok());
                let phase = doc
                    .as_ref()
                    .and_then(|d| d.get("phase"))
                    .and_then(Json::as_str);
                if phase != Some(f.phase.name()) {
                    problems.push(format!(
                        "{}: expectation phase {phase:?} differs from fixture",
                        f.id
                    ));
                }
            }
        }
    }
    collect_stray(&corpus, &expected_files, &mut problems);
    for p in &problems {
        println!("{p}");
    }
    println!("{} fixtures, {} problems", fixtures.len(), problems.len());
    Ok(u8::from(!problems.is_empty()))
}

fn collect_stray(
    dir: &Path,
    known: &std::collections::BTreeSet<PathBuf>,
    problems: &mut Vec<String>,
) {
    let Ok(read) = fs::read_dir(dir) else { return };
    for entry in read.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if path.join("conform.meta").exists() {
                continue;
            }
            collect_stray(&path, known, problems);
        } else if path.to_string_lossy().ends_with(".expected.json") && !known.contains(&path) {
            problems.push(format!("{}: expectation without a fixture", path.display()));
        }
    }
}

fn parse_seeds(args: &Args) -> Result<(u64, u64), String> {
    let text = args.one("seeds").unwrap_or("0..100");
    let (a, b) = text.split_once("..").ok_or("--seeds wants A..B")?;
    let (a, b): (u64, u64) = (
        a.parse().map_err(|_| "--seeds wants A..B")?,
        b.parse().map_err(|_| "--seeds wants A..B")?,
    );
    Ok((a, b))
}

struct Kind {
    dir: &'static str,
    phase: Phase,
    make: fn(u64) -> fuzz::Generated,
}

fn kind_of(args: &Args) -> Result<Kind, String> {
    match args.one("kind").unwrap_or("run") {
        "run" => Ok(Kind {
            dir: "fuzz/run",
            phase: Phase::Run,
            make: fuzz::program,
        }),
        "type" => Ok(Kind {
            dir: "fuzz/types",
            phase: Phase::Check,
            make: fuzz::type_error,
        }),
        "syntax" => Ok(Kind {
            dir: "fuzz/syntax",
            phase: Phase::Parse,
            make: fuzz::syntax_error,
        }),
        other => Err(format!("unknown --kind {other}")),
    }
}

/// Write generated fixtures `seed-NNNN.ms` into `dir`.
fn write_generated(dir: &Path, kind: &Kind, seeds: (u64, u64)) -> Result<usize, String> {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let mut n = 0;
    for seed in seeds.0..seeds.1 {
        let g = (kind.make)(seed);
        let mut tags: Vec<String> = g.tags.iter().map(|t| t.to_string()).collect();
        if kind.phase == Phase::Run {
            tags.push("stdlib-io".into());
        }
        tags.sort();
        tags.dedup();
        let meta = Meta {
            tags,
            phase: Some(kind.phase),
            origin: format!(
                "ms-conform fuzz-gen --kind {} seed {seed}",
                args_kind_name(kind)
            ),
            deterministic: true,
            ..Meta::default()
        };
        let text = fixture::render_meta(&meta) + &g.source;
        fs::write(dir.join(format!("seed-{seed:04}.ms")), text).map_err(|e| e.to_string())?;
        n += 1;
    }
    Ok(n)
}

fn args_kind_name(kind: &Kind) -> &'static str {
    match kind.phase {
        Phase::Run => "run",
        Phase::Check => "type",
        _ => "syntax",
    }
}

fn cmd_fuzz_gen(args: &Args) -> Result<u8, String> {
    let kind = kind_of(args)?;
    let dir = args.corpus()?.join(kind.dir);
    let n = write_generated(&dir, &kind, parse_seeds(args)?)?;
    println!(
        "wrote {n} fixtures to {}; run `ms-conform record --id {}/` next",
        dir.display(),
        kind.dir
    );
    Ok(0)
}

fn cmd_fuzz(args: &Args) -> Result<u8, String> {
    let kind = kind_of(args)?;
    let seeds = parse_seeds(args)?;
    let temp = std::env::temp_dir().join(format!("ms-conform-fuzz-{}", std::process::id()));
    let _ = fs::remove_dir_all(&temp);
    write_generated(&temp.join("fixtures"), &kind, seeds)?;
    let (fixtures, _) = fixture::discover(&temp.join("fixtures"));
    let selected: Vec<&Fixture> = fixtures.iter().collect();
    let mut oracle = context(args, "oracle")?;
    oracle.scratch = temp.join("scratch-oracle");
    let mut candidate = context(args, "ms")?;
    candidate.scratch = temp.join("scratch-candidate");
    eprintln!(
        "fuzzing {} {} programs: oracle {} vs {}",
        selected.len(),
        args_kind_name(&kind),
        oracle.ms.display(),
        candidate.ms.display()
    );
    let cases = record::diff_binaries(&oracle, &candidate, &selected, args.jobs()?);
    print_summary(&cases);
    if let Some(save) = args.one("save") {
        fs::create_dir_all(save).map_err(|e| e.to_string())?;
        for c in cases.iter().filter(|c| c.outcome == runner::Outcome::Fail) {
            let src = temp.join("fixtures").join(format!("{}.ms", c.id));
            let name = format!("{}.ms", c.id);
            let _ = fs::copy(&src, Path::new(save).join(&name));
            let _ = fs::write(Path::new(save).join(format!("{}.diff", c.id)), &c.diff);
        }
    }
    let code = u8::from(report::has_regressions(&cases));
    if !args.has("keep") {
        let _ = fs::remove_dir_all(&temp);
    }
    Ok(code)
}

fn cmd_harvest(args: &Args) -> Result<u8, String> {
    let repo = PathBuf::from(args.one("repo").unwrap_or("."));
    let corpus = args
        .corpus()
        .unwrap_or_else(|_| repo.join("tests/conformance/fixtures"));
    let ms = args.ms("ms");
    let mut candidates = Vec::new();
    if !args.has("no-tree") {
        candidates.extend(harvest::scan_tree(&repo));
    }
    if !args.has("no-docs") {
        candidates.extend(harvest::scan_docs(&repo));
    }
    eprintln!("{} candidates", candidates.len());
    let scratch = std::env::temp_dir().join(format!("ms-conform-harvest-{}", std::process::id()));
    let opts = harvest::HarvestOpts {
        jobs: args.jobs()?,
        formatter_twins: !args.has("no-twins"),
    };
    let summary = harvest::harvest(&ms, &scratch, &corpus, candidates, &opts);
    let _ = fs::remove_dir_all(&scratch);
    println!(
        "{} fixtures written, {} duplicates dropped, {} unusable",
        summary.written,
        summary.duplicates,
        summary.unusable.len()
    );
    for (phase, n) in &summary.by_phase {
        println!("  {phase:<6} {n}");
    }
    for (origin, reason) in &summary.unusable {
        println!("UNUSABLE {origin}: {reason}");
    }
    Ok(0)
}

fn cmd_retag(args: &Args) -> Result<u8, String> {
    let n = harvest::retag_tiers(&args.corpus()?);
    println!("{n} fixtures retagged");
    Ok(0)
}
