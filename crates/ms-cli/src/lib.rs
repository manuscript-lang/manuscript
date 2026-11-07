//! The `ms` command line: dispatch, option parsing, help text, status codes.
//!
//! Exit statuses: `0` success; `1` the command ran and failed (diagnostics,
//! failing tests, I/O errors); `2` usage error (bad flags or arguments, nothing
//! was run); and the program's own status for `run`.

// Links the msrt_* runtime symbols that the standard-library crates reference.
#[cfg(test)]
use ms_rt as _;
pub mod analysis;
pub mod backend;
mod commands;
pub mod diagnostic;
mod duration;
pub mod engine;
pub mod fault;
pub mod fmt;
pub mod help;
mod help_text;
pub mod init;
pub mod invocation;
pub mod json;
pub mod process;
pub mod profile;
mod regexp;
mod snippet;
pub mod util;
pub mod verify;

pub use ms_driver::project::quoting::quote;

use backend::{
    AnalysisCommand, AnalysisRequest, BuildRequest, DiagramRequest, Io, OutputRequest, RunRequest,
    TestRequest, finish,
};
use engine::Engine;
use invocation::{parse_invocation, requests_help, validate};
use ms_build::Lower;

/// The release version, from `.msversion`.
pub const VERSION: &str = env!("MS_VERSION");

/// Run `ms` with `args` (without the program name) and return the exit status.
pub fn run<L: Lower>(
    syms: ms_syntax::Names,
    args: &[String],
    engine: &Engine<L>,
    io: &mut Io,
) -> i32 {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        let _ = write!(io.stdout, "{}", help::HELP);
        return 0;
    }
    if args[0] == "--version" || args[0] == "version" {
        return commands::run_version(&args[0], &args[1..], io);
    }
    let Some(usage) = help::command_help(&args[0]) else {
        unknown_command(io, &args[0]);
        return 2;
    };
    let defaulted = default_project_target(args);
    let args = defaulted.as_deref().unwrap_or(args);
    if requests_help(&args[1..]) {
        let _ = write!(io.stdout, "{usage}");
        return 0;
    }
    match args[0].as_str() {
        "help" => commands::run_help(&args[1..], io),
        "init" => init::run_init(&args[1..], io),
        "verify" => verify::run_verify(syms, &args[1..], engine, io),
        "fmt" => fmt::run_format(syms, &args[1..], io),
        "lsp" => commands::run_lsp(syms, args, io),
        "review" => commands::run_review(syms, args, io),
        "search_symbol" => commands::run_search_symbol(syms, args, io),
        "guide" => commands::run_guide(args, io),
        _ => run_source_command(syms, args, &usage, engine, io),
    }
}

/// Commands that take a source file or project and default to `./ms.toml`.
const PROJECT_COMMANDS: &[&str] = &[
    "check", "lint", "build", "emit", "run", "test", "bench", "fmt", "verify", "inspect",
    "diagram", "review", "profile",
];

/// Inside a project directory, `ms run` means `ms run ms.toml`: when the command
/// names no target (nothing after it, or only options and `-- program arguments`), insert
/// the manifest in the current directory.
fn default_project_target(args: &[String]) -> Option<Vec<String>> {
    if !PROJECT_COMMANDS.contains(&args[0].as_str()) {
        return None;
    }
    if args.len() > 1 && args[1] != "--" && !args[1].starts_with('-') {
        return None;
    }
    if !std::path::Path::new("ms.toml").is_file() {
        return None;
    }
    let mut out = vec![args[0].clone(), "ms.toml".to_string()];
    out.extend_from_slice(&args[1..]);
    Some(out)
}

/// Name the nearest command and list the rest.
pub fn unknown_command(io: &mut Io, name: &str) {
    let _ = writeln!(io.stderr, "unknown command: {name}");
    let mut best: Option<&str> = None;
    let mut best_distance = 3;
    for candidate in help::COMMAND_NAMES {
        let d = ms_check::api::hints::edit_distance(name, candidate);
        if d < best_distance {
            best = Some(candidate);
            best_distance = d;
        }
    }
    if let Some(best) = best {
        let _ = writeln!(io.stderr, "Did you mean 'ms {best}'?");
    } else if name.ends_with(".ms") || name.ends_with(".toml") || name.contains(['/', '\\']) {
        let _ = writeln!(
            io.stderr,
            "'{name}' looks like a path; commands come first, e.g. 'ms run {name}' or 'ms check {name}'."
        );
    }
    let _ = writeln!(
        io.stderr,
        "Commands: {}. Run 'ms --help' for details.",
        help::COMMAND_NAMES.join(", ")
    );
}

/// A command that takes a source file or project: parse and validate its
/// options, then hand the request to the engine.
fn run_source_command<L: Lower>(
    syms: ms_syntax::Names,
    args: &[String],
    usage: &str,
    engine: &Engine<L>,
    io: &mut Io,
) -> i32 {
    if args.len() < 2 {
        let _ = writeln!(
            io.stderr,
            "ms {0}: missing the file argument; pass a .ms file or a project ms.toml, e.g. ms {0} ms.toml\n",
            args[0]
        );
        let _ = write!(io.stderr, "{usage}");
        return 2;
    }
    let mut inv = match parse_invocation(args, io) {
        Ok(inv) => inv,
        Err(status) => return status,
    };
    let plan = match validate(&mut inv, io) {
        Ok(plan) => plan,
        Err(status) => return status,
    };
    engine.set_static_libc(inv.static_libc);
    let result = match inv.command.as_str() {
        "check" | "lint" => {
            let command = if inv.command == "check" {
                AnalysisCommand::Check
            } else {
                AnalysisCommand::Lint
            };
            let request = AnalysisRequest {
                command,
                targets: inv.targets.clone(),
                json: inv.structured,
                watch: inv.watch,
                fix: inv.fix,
                deny_warnings: inv.deny_warnings,
                with_text: inv.with_text,
            };
            engine::analysis(syms, &request, io)
        }
        "profile" => {
            let build = |request: &BuildRequest, io: &mut Io| engine.build(syms, request, io);
            return profile::run_profile(&inv, plan.build_type, &build, io);
        }
        "build" => engine.build(
            syms,
            &BuildRequest {
                filename: inv.filename.clone(),
                output: inv.output.clone(),
                build_type: plan.build_type,
                json: inv.structured,
                link: inv.link.clone(),
            },
            io,
        ),
        "run" => engine.run(
            syms,
            &RunRequest {
                filename: inv.filename.clone(),
                build_type: plan.build_type,
                link: inv.link.clone(),
                watch: inv.watch,
                json: inv.structured,
                arguments: inv.arguments.clone(),
            },
            io,
        ),
        "test" => engine.test(
            syms,
            &TestRequest {
                filename: inv.filename.clone(),
                extra: inv.targets.iter().skip(1).cloned().collect(),
                build_type: plan.build_type,
                link: inv.link.clone(),
                json: inv.structured,
                watch: inv.watch,
                arguments: inv.arguments.clone(),
            },
            io,
        ),
        "bench" => engine.bench(
            syms,
            &TestRequest {
                filename: inv.filename.clone(),
                extra: Vec::new(),
                build_type: plan.build_type,
                link: inv.link.clone(),
                json: inv.structured,
                watch: false,
                arguments: inv.arguments.clone(),
            },
            io,
        ),
        "emit" => engine.emit(
            syms,
            &OutputRequest {
                filename: inv.filename.clone(),
                output: inv.output.clone(),
                json: inv.structured,
            },
            io,
        ),
        "inspect" => engine::inspect(
            syms,
            &OutputRequest {
                filename: inv.filename.clone(),
                output: inv.output.clone(),
                json: inv.structured,
            },
            io,
        ),
        _ => engine::diagram(
            syms,
            &DiagramRequest {
                filename: inv.filename.clone(),
                output: inv.output.clone(),
                format: inv.format.clone(),
                view: inv.view.clone(),
                entity: inv.entity.clone(),
                depth: inv.depth,
                diff: inv.diff.clone(),
                json: inv.structured,
            },
            io,
        ),
    };
    finish(result, io)
}
