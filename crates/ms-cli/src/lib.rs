//! The `ms` command line: dispatch, option parsing, help text, status codes.
//!
//! Exit statuses: `0` success; `1` the command ran and failed (diagnostics,
//! failing tests, I/O errors); `2` usage error (bad flags or arguments, nothing
//! was run); the program's own status for `run`; and
//! [`backend::EXIT_NOT_IMPLEMENTED`] (`70`) when the command needs an engine
//! that the Rust implementation does not provide yet.
//!
//! Engines plug in through [`backend::Backend`]; see that module.

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
pub mod util;
pub mod verify;

pub use ms_project::strconv::quote;

use backend::{
    AnalysisCommand, AnalysisRequest, Backend, BuildRequest, DiagramRequest, Io, OutputRequest,
    RunRequest, TestRequest, finish,
};
use invocation::{parse_invocation, requests_help, validate};

/// The release version, from `.msversion`.
pub const VERSION: &str = env!("MS_VERSION");

/// Run `ms` with `args` (without the program name) and return the exit status.
pub fn run(args: &[String], backend: &dyn Backend, io: &mut Io) -> i32 {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        let _ = write!(io.stdout, "{}", help::HELP);
        return 0;
    }
    if args[0] == "--version" || args[0] == "version" {
        return commands::run_version(&args[0], &args[1..], backend, io);
    }
    let Some(usage) = help::command_help(&args[0]) else {
        unknown_command(io, &args[0]);
        return 2;
    };
    if requests_help(&args[1..]) {
        let _ = write!(io.stdout, "{usage}");
        return 0;
    }
    match args[0].as_str() {
        "help" => commands::run_help(&args[1..], io),
        "init" => init::run_init(&args[1..], io),
        "verify" => verify::run_verify(&args[1..], backend, io),
        "fmt" => fmt::run_format(&args[1..], backend, io),
        "lsp" => commands::run_lsp(args, backend, io),
        "review" => commands::run_review(args, backend, io),
        "search_symbol" => commands::run_search_symbol(args, backend, io),
        "guide" => commands::run_guide(args, backend, io),
        _ => run_source_command(args, &usage, backend, io),
    }
}

/// Name the nearest command and list the rest.
pub fn unknown_command(io: &mut Io, name: &str) {
    let _ = writeln!(io.stderr, "unknown command: {name}");
    let mut best: Option<&str> = None;
    let mut best_distance = 3;
    for candidate in help::COMMAND_NAMES {
        let d = ms_check::hints::edit_distance(name, candidate);
        if d < best_distance {
            best = Some(candidate);
            best_distance = d;
        }
    }
    if let Some(best) = best {
        let _ = writeln!(io.stderr, "Did you mean 'ms {best}'?");
    } else if name.ends_with(".ms") || name.ends_with(".toml") || name.contains('/') {
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
/// options, then hand the request to the backend.
fn run_source_command(args: &[String], usage: &str, backend: &dyn Backend, io: &mut Io) -> i32 {
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
            };
            match command {
                AnalysisCommand::Check => backend.check(&request, io),
                AnalysisCommand::Lint => backend.lint(&request, io),
            }
        }
        "profile" => return profile::run_profile(&inv, plan.build_type, backend, io),
        "build" => backend.build(
            &BuildRequest {
                filename: inv.filename.clone(),
                output: inv.output.clone(),
                build_type: plan.build_type,
                json: inv.structured,
            },
            io,
        ),
        "run" => backend.run(
            &RunRequest {
                filename: inv.filename.clone(),
                build_type: plan.build_type,
                watch: inv.watch,
                json: inv.structured,
                arguments: inv.arguments.clone(),
            },
            io,
        ),
        "test" => backend.test(
            &TestRequest {
                filename: inv.filename.clone(),
                build_type: plan.build_type,
                json: inv.structured,
                watch: inv.watch,
                arguments: inv.arguments.clone(),
            },
            io,
        ),
        "emit" => backend.emit(
            &OutputRequest {
                filename: inv.filename.clone(),
                output: inv.output.clone(),
                json: inv.structured,
            },
            io,
        ),
        "inspect" => backend.inspect(
            &OutputRequest {
                filename: inv.filename.clone(),
                output: inv.output.clone(),
                json: inv.structured,
            },
            io,
        ),
        _ => backend.diagram(
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
