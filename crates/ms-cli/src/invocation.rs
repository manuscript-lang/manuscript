//! Option parsing and validation for the source commands (`check`, `lint`,
//! `build`, `emit`, `run`, `test`, `inspect`, `diagram`, `profile`).
//! `ms profile` is described in [`crate::profile`].

use crate::backend::{BuildType, Io};
use crate::regexp;
use crate::util::{required_value, resolve_input, split_value_option, usage_error};
use ms_driver::project::quoting::quote;

/// Long options that take a value (also accepted as `--flag=value`).
pub const VALUE_OPTIONS: &[&str] = &[
    "-o",
    "--output",
    "--out-dir",
    "--build-type",
    "--timeout",
    "--filter",
    "--test",
    "--bench",
    "--match",
    "--exclude",
    "--repeat",
    "--shuffle",
    "--runs",
    "--seed",
    "--fuzz",
    "--time",
    "--samples",
    "--iterations",
    "--format",
    "--view",
    "--entity",
    "--depth",
    "--diff",
    "--top",
    "--link",
];

/// The `--view` names of `ms diagram`.
pub const VIEWS: &[&str] = &ms_tooling::views::VIEWS;

/// Commands that accept `--json`.
pub const JSON_COMMANDS: &[&str] = &[
    "check",
    "lint",
    "test",
    "bench",
    "run",
    "build",
    "profile",
    "inspect",
    "diagram",
    "emit",
    "fmt",
    "verify",
    "search_symbol",
];

#[derive(Debug, Default)]
pub struct Invocation {
    pub command: String,
    pub filename: String,
    /// `check` and `lint` accept many targets.
    pub analysis: bool,
    pub targets: Vec<String>,
    pub output: String,
    /// `--link`: extra objects and static libraries for `extern fn` symbols.
    pub link: Vec<String>,
    pub format_check: bool,
    pub structured: bool,
    pub watch: bool,
    pub fix: bool,
    /// `--deny-warnings`: lint warnings fail the command.
    pub deny_warnings: bool,
    pub build_type_name: String,
    pub test_timeout: String,
    pub test_filter: String,
    pub test_options: Vec<String>,
    pub format: String,
    pub view: String,
    pub entity: String,
    pub diff: String,
    pub depth: usize,
    /// `ms profile --top`; zero means the default.
    pub top: usize,
    /// Forwarded to the program after `--`.
    pub arguments: Vec<String>,
}

impl Invocation {
    pub fn is_one_of(&self, commands: &[&str]) -> bool {
        commands.contains(&self.command.as_str())
    }
}

/// Read the command, its input file and options. `Err` carries the exit
/// status for a problem already reported.
pub fn parse_invocation(args: &[String], io: &mut Io) -> Result<Invocation, i32> {
    let mut inv = Invocation {
        command: args[0].clone(),
        filename: args[1].clone(),
        ..Default::default()
    };
    if inv.filename.is_empty() {
        return Err(usage_error(
            io,
            format!(
                "ms {}: the file argument is empty; pass a .ms file, directory, or ms.toml",
                inv.command
            ),
        ));
    }
    inv.analysis = inv.is_one_of(&["check", "lint"]);
    let (mut first, mut positional) = (1, false);
    if inv.analysis && inv.filename == "--" {
        if args.len() == 2 {
            return Err(usage_error(
                io,
                format!(
                    "ms {}: missing a target; pass .ms files, directories, or ms.toml",
                    inv.command
                ),
            ));
        }
        first = 2;
        inv.filename = args[2].clone();
        positional = true;
    }
    if inv.filename.starts_with('-') && inv.filename != "--" && !positional {
        return Err(usage_error(
            io,
            format!(
                "unknown option {} for ms {}; run 'ms help {}' for its options (put the file first, then options)",
                inv.filename, inv.command, inv.command
            ),
        ));
    }
    if !inv.analysis {
        match resolve_input(&inv.command, &inv.filename) {
            Ok(filename) => inv.filename = filename,
            Err(message) => {
                let _ = writeln!(io.stderr, "{message}");
                return Err(2);
            }
        }
    }
    inv.targets = vec![inv.filename.clone()];
    parse_options(&mut inv, args, first, positional, io)?;
    if inv.analysis && inv.targets.iter().any(String::is_empty) {
        return Err(usage_error(
            io,
            format!(
                "ms {}: an input argument is empty; pass a .ms file, directory, or ms.toml",
                inv.command
            ),
        ));
    }
    Ok(inv)
}

fn parse_options(
    inv: &mut Invocation,
    args: &[String],
    first: usize,
    positional: bool,
    io: &mut Io,
) -> Result<(), i32> {
    let mut i = first + 1;
    while i < args.len() {
        if positional {
            inv.targets.push(args[i].clone());
            i += 1;
            continue;
        }
        let (flag, value, inline) = split_value_option(&args[i], VALUE_OPTIONS);
        match flag {
            "--" => {
                if inv.analysis {
                    inv.targets.extend_from_slice(&args[i + 1..]);
                } else {
                    inv.arguments = args[i + 1..].to_vec();
                }
                return Ok(());
            }
            "--watch" => inv.watch = true,
            "--fix" => inv.fix = true,
            "--deny-warnings" => inv.deny_warnings = true,
            "--check" => inv.format_check = true,
            "--json" => inv.structured = true,
            "--build-type" => {
                let Some(value) = required_value(args, &mut i, value, inline) else {
                    return Err(usage_error(
                        io,
                        "--build-type requires a build type; use Debug, Release, or MinSizeRel",
                    ));
                };
                if !inv.build_type_name.is_empty() {
                    return Err(usage_error(
                        io,
                        "--build-type may only be specified once; remove the duplicate flag",
                    ));
                }
                inv.build_type_name = value.to_string();
            }
            "--list" | "--fail-fast" => inv.test_options.push(flag.to_string()),
            "--test" | "--match" | "--exclude" | "--repeat" | "--shuffle" | "--runs" | "--seed"
            | "--fuzz" | "--time" | "--samples" | "--iterations" | "--bench" => {
                let Some(value) = required_value(args, &mut i, value, inline) else {
                    return Err(usage_error(
                        io,
                        format!("{flag} requires a value; run 'ms help test' for examples"),
                    ));
                };
                if (flag == "--match" || flag == "--exclude")
                    && let Err(error) = regexp::validate(value)
                {
                    return Err(usage_error(
                        io,
                        format!("invalid {flag}: {error}; supply a valid regular expression"),
                    ));
                }
                if matches!(flag, "--repeat" | "--runs" | "--samples" | "--iterations")
                    && !value.parse::<i64>().is_ok_and(|n| n > 0)
                {
                    return Err(usage_error(
                        io,
                        format!("invalid {flag}; use a positive integer"),
                    ));
                }
                if matches!(flag, "--shuffle" | "--seed") && value.parse::<i64>().is_err() {
                    return Err(usage_error(
                        io,
                        format!("invalid {flag}; use an integer seed"),
                    ));
                }
                if flag == "--time"
                    && !crate::duration::parse(value).is_some_and(|n| n >= 1_000_000)
                {
                    return Err(usage_error(
                        io,
                        format!(
                            "invalid --time {}; use a duration of at least 1ms such as 200ms or 1s",
                            quote(value)
                        ),
                    ));
                }
                if flag == "--fuzz" && !crate::duration::parse(value).is_some_and(|n| n > 0) {
                    return Err(usage_error(
                        io,
                        format!(
                            "invalid --fuzz {}; use a positive duration such as 30s or 5m",
                            quote(value)
                        ),
                    ));
                }
                // `--bench` names a bench the way `--test` names a test.
                let flag = if flag == "--bench" { "--test" } else { flag };
                inv.test_options.push(format!("{flag}={value}"));
            }
            "--timeout" | "--filter" => {
                let Some(value) = required_value(args, &mut i, value, inline) else {
                    let example = if flag == "--timeout" {
                        "--timeout 30s"
                    } else {
                        "--filter \"test name\""
                    };
                    return Err(usage_error(
                        io,
                        format!("{flag} requires a value, e.g. {example}"),
                    ));
                };
                if flag == "--filter" {
                    inv.test_filter = value.to_string();
                    i += 1;
                    continue;
                }
                if !crate::duration::parse(value).is_some_and(|nanos| nanos >= 0) {
                    return Err(usage_error(
                        io,
                        format!(
                            "invalid --timeout {value:?}; use a duration such as 30s or 2m, or 0 to disable"
                        ),
                    ));
                }
                inv.test_timeout = value.to_string();
            }
            "--format" => {
                let Some(value) = required_value(args, &mut i, value, inline) else {
                    return Err(usage_error(
                        io,
                        "--format requires a name, e.g. --format mermaid",
                    ));
                };
                inv.format = value.to_string();
            }
            "--view" | "--entity" | "--depth" | "--diff" | "--top" => {
                let Some(value) = required_value(args, &mut i, value, inline) else {
                    let help = if flag == "--top" {
                        "profile"
                    } else {
                        "diagram"
                    };
                    return Err(usage_error(
                        io,
                        format!("{flag} requires a value; run 'ms help {help}' for examples"),
                    ));
                };
                match flag {
                    "--view" => inv.view = value.to_string(),
                    "--entity" => inv.entity = value.to_string(),
                    "--diff" => inv.diff = value.to_string(),
                    _ => match value.parse::<i64>() {
                        Ok(n) if n > 0 => {
                            if flag == "--depth" {
                                inv.depth = n as usize;
                            } else {
                                inv.top = n as usize;
                            }
                        }
                        _ => {
                            return Err(usage_error(
                                io,
                                format!("invalid {flag}; use a positive integer"),
                            ));
                        }
                    },
                }
            }
            "--link" => {
                let Some(value) = required_value(args, &mut i, value, inline) else {
                    return Err(usage_error(
                        io,
                        "--link requires a path argument, e.g. --link native/libgreet.a",
                    ));
                };
                inv.link.push(value.to_string());
            }
            "-o" | "--output" | "--out-dir" => {
                let Some(value) = required_value(args, &mut i, value, inline) else {
                    return Err(usage_error(io, path_requirement(flag)));
                };
                set_path(inv, flag, value, io)?;
            }
            _ => {
                if !args[i].starts_with('-') {
                    if inv.analysis {
                        if args[i].is_empty() {
                            return Err(usage_error(
                                io,
                                format!(
                                    "ms {}: an input argument is empty; pass a .ms file, directory, or ms.toml",
                                    inv.command
                                ),
                            ));
                        }
                        inv.targets.push(args[i].clone());
                        i += 1;
                        continue;
                    }
                    return Err(usage_error(
                        io,
                        format!(
                            "unexpected extra argument {} (ms {} takes one file; arguments for the program go after --)",
                            args[i], inv.command
                        ),
                    ));
                }
                return Err(usage_error(
                    io,
                    format!(
                        "unknown option {} for ms {}; run 'ms help {}' for its options (arguments for the program go after --)",
                        args[i], inv.command, inv.command
                    ),
                ));
            }
        }
        i += 1;
    }
    Ok(())
}

fn path_requirement(flag: &str) -> String {
    let example = match flag {
        "--out-dir" => "profile-bundle",
        _ => "out.txt",
    };
    format!("{flag} requires a path argument, e.g. {flag} {example}")
}

fn set_path(inv: &mut Invocation, flag: &str, value: &str, io: &mut Io) -> Result<(), i32> {
    if flag == "--out-dir" && inv.command != "profile" {
        return Err(usage_error(
            io,
            format!(
                "--out-dir is valid only for ms profile, not ms {}; use -o for commands that write a file",
                inv.command
            ),
        ));
    }
    if flag != "--out-dir" && inv.command == "profile" {
        return Err(usage_error(
            io,
            format!("{flag} is not valid for ms profile; use --out-dir for the bundle directory"),
        ));
    }
    inv.output = value.to_string();
    Ok(())
}

/// The validated command, ready for dispatch.
#[derive(Debug)]
pub struct Plan {
    pub build_type: BuildType,
}

fn invalid_flag(command: &str, format_check: bool, structured: bool) -> String {
    if format_check && command != "fmt" {
        format!("--check is valid only for ms fmt, not ms {command}")
    } else if structured {
        format!(
            "--json is valid only for ms {}, not ms {command}",
            JSON_COMMANDS.join(", ")
        )
    } else {
        format!("an option is not valid for ms {command}")
    }
}

/// Reject option combinations the command does not accept and select the
/// build type. Each problem is a cause and a fix.
pub fn validate(inv: &mut Invocation, io: &mut Io) -> Result<Plan, i32> {
    let command = inv.command.clone();
    let help_hint = format!("run 'ms help {command}' for its options");
    if !inv.is_one_of(&[
        "check", "lint", "inspect", "diagram", "emit", "build", "run", "profile", "test", "bench",
    ]) {
        crate::unknown_command(io, &command);
        return Err(2);
    }
    if !inv.format.is_empty() && command != "diagram" {
        return Err(usage_error(
            io,
            format!(
                "--format is valid only for ms diagram and ms review, not ms {command}; run 'ms help {command}' for its options"
            ),
        ));
    }
    if (!inv.view.is_empty() || !inv.entity.is_empty() || inv.depth != 0 || !inv.diff.is_empty())
        && command != "diagram"
    {
        return Err(usage_error(
            io,
            format!(
                "--view, --entity, --depth, and --diff are valid only for ms diagram, not ms {command}; run 'ms help {command}' for its options"
            ),
        ));
    }
    if inv.top != 0 && command != "profile" {
        return Err(usage_error(
            io,
            format!("--top is valid only for ms profile, not ms {command}; {help_hint}"),
        ));
    }
    if !inv.view.is_empty() && !VIEWS.contains(&inv.view.as_str()) {
        return Err(usage_error(
            io,
            format!(
                "unknown --view {} for ms diagram; use {}",
                quote(&inv.view),
                VIEWS.join(", ")
            ),
        ));
    }
    if !inv.diff.is_empty() && inv.view.is_empty() && inv.entity.is_empty() {
        return Err(usage_error(
            io,
            "--diff marks a scoped view; add --view or --entity, e.g. ms diagram ms.toml --view flow --entity save --diff change.patch",
        ));
    }
    if inv.depth != 0 && inv.view.is_empty() && inv.entity.is_empty() {
        return Err(usage_error(
            io,
            "--depth needs --view or --entity; run 'ms help diagram' for examples",
        ));
    }
    if command == "diagram" && inv.structured && !inv.format.is_empty() {
        return Err(usage_error(
            io,
            "--json and --format cannot be combined; --json emits the diagram tree",
        ));
    }
    if command == "diagram"
        && !inv.format.is_empty()
        && inv.format != "ascii"
        && inv.format != "mermaid"
    {
        return Err(usage_error(
            io,
            format!(
                "unknown --format {} for ms diagram; use ascii or mermaid",
                quote(&inv.format)
            ),
        ));
    }
    if !inv.output.is_empty() && !inv.is_one_of(&["build", "emit", "inspect", "diagram", "profile"])
    {
        return Err(usage_error(
            io,
            format!(
                "-o and --output are valid only for ms build, emit, inspect, diagram, or profile, not ms {command}; run 'ms help {command}' for its options"
            ),
        ));
    }
    if (!inv.test_timeout.is_empty() || !inv.test_filter.is_empty() || !inv.test_options.is_empty())
        && !inv.is_one_of(&["test", "bench"])
    {
        return Err(usage_error(
            io,
            format!(
                "test selection options are valid only for ms test and ms bench, not ms {command}; run 'ms help {command}' for the options this command accepts"
            ),
        ));
    }
    let only = |names: &[&str]| {
        inv.test_options
            .iter()
            .map(|option| {
                option
                    .split_once('=')
                    .map_or(option.as_str(), |(flag, _)| flag)
            })
            .find(|flag| names.contains(flag))
    };
    if command == "test"
        && let Some(flag) = only(&["--time", "--samples", "--iterations"])
    {
        return Err(usage_error(
            io,
            format!(
                "{flag} is valid only for ms bench; run 'ms help test' for the options this command accepts"
            ),
        ));
    }
    if command == "bench"
        && let Some(flag) = only(&["--runs", "--seed", "--fuzz", "--shuffle"])
    {
        return Err(usage_error(
            io,
            format!(
                "{flag} is valid only for ms test; run 'ms help bench' for the options this command accepts"
            ),
        ));
    }
    if inv.is_one_of(&["test", "bench"]) {
        let mut test_args = inv.test_options.clone();
        if !inv.test_timeout.is_empty() {
            test_args.push(format!("--timeout={}", inv.test_timeout));
        }
        if !inv.test_filter.is_empty() {
            test_args.push(format!("--filter={}", inv.test_filter));
        }
        if !inv.arguments.is_empty() {
            test_args.push("--".to_string());
            test_args.append(&mut inv.arguments);
        }
        inv.arguments = test_args;
    }
    if inv.watch && inv.structured {
        return Err(usage_error(
            io,
            "--json cannot be combined with --watch; remove --watch for one versioned result",
        ));
    }
    if inv.fix && (!inv.is_one_of(&["check", "lint"]) || inv.watch) {
        return Err(usage_error(
            io,
            format!(
                "--fix requires check or lint without --watch, not {command}; use ms check <file> --fix"
            ),
        ));
    }
    if inv.deny_warnings && command != "lint" {
        return Err(usage_error(
            io,
            format!(
                "--deny-warnings requires lint, not {command}; use ms lint <file> --deny-warnings"
            ),
        ));
    }
    if inv.watch && !inv.is_one_of(&["check", "lint", "run", "test"]) {
        return Err(usage_error(
            io,
            format!(
                "--watch requires check, lint, run, or test, not {command}; use ms check <file> --watch or ms run <file> --watch"
            ),
        ));
    }
    if (inv.format_check && command != "fmt") || (inv.structured && !inv.is_one_of(JSON_COMMANDS)) {
        return Err(usage_error(
            io,
            format!(
                "{}; run 'ms help {command}' for the options this command accepts",
                invalid_flag(&command, inv.format_check, inv.structured)
            ),
        ));
    }
    let kind = match BuildType::parse(&inv.build_type_name) {
        Ok(kind) => kind,
        Err(message) => {
            let _ = writeln!(io.stderr, "{message}");
            return Err(2);
        }
    };
    if !inv.link.is_empty() && !inv.is_one_of(&["build", "run", "test", "bench"]) {
        return Err(usage_error(
            io,
            format!("--link requires build, run, test, or bench, not {command}; remove the flag"),
        ));
    }
    if !inv.build_type_name.is_empty()
        && !inv.is_one_of(&["build", "run", "test", "bench", "profile"])
    {
        return Err(usage_error(
            io,
            format!(
                "--build-type requires build, run, test, bench, or profile, not {command}; remove the flag"
            ),
        ));
    }
    Ok(Plan { build_type: kind })
}

/// `--help` scanning: a flag value is not a help request, even if spelled `--help`.
pub fn requests_help(args: &[String]) -> bool {
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--" => return false,
            "-h" | "--help" => return true,
            flag if VALUE_OPTIONS.contains(&flag) || ["--limit", "--explain"].contains(&flag) => {
                i += 1;
            }
            _ => {}
        }
        i += 1;
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn help_scanning_respects_option_values_and_the_separator() {
        for flag in VALUE_OPTIONS.iter().chain(["--limit", "--explain"].iter()) {
            for value in ["-h", "--help"] {
                let args = [flag.to_string(), value.to_string()];
                assert!(!requests_help(&args), "{args:?}");
                assert!(requests_help(&[
                    args[0].clone(),
                    args[1].clone(),
                    "--help".into()
                ]));
            }
        }
        assert!(!requests_help(&["--".into(), "--help".into()]));
        assert!(requests_help(&["--entity=--help".into(), "--help".into()]));
    }
}
