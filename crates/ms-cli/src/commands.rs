//! Argument parsing for the standalone commands: `review`, `search_symbol`,
//! `help`, `version`, `lsp` and `guide`.

use crate::backend::{Io, ReviewRequest, SearchSymbolRequest, finish};
use crate::engine;
use crate::help;
use crate::util::{required_value, resolve_input, split_value_option, usage_error};

pub const DEFAULT_SYMBOL_LIMIT: usize = 5;
pub const MAX_SYMBOL_LIMIT: usize = 10;

pub fn run_help(args: &[String], io: &mut Io) -> i32 {
    match args {
        [] => {
            let _ = write!(io.stdout, "{}", help::HELP);
            0
        }
        [command] => {
            if let Some(usage) = help::command_help(command) {
                let _ = write!(io.stdout, "{usage}");
                return 0;
            }
            crate::unknown_command(io, command);
            2
        }
        _ => help_usage(io),
    }
}

fn help_usage(io: &mut Io) -> i32 {
    let _ = writeln!(io.stderr, "usage: ms help [command]");
    let _ = writeln!(io.stderr, "Run 'ms --help' to list commands.");
    2
}

pub fn run_version(command: &str, args: &[String], io: &mut Io) -> i32 {
    if command == "version" && args.len() == 1 && (args[0] == "--help" || args[0] == "-h") {
        let _ = write!(
            io.stdout,
            "{}",
            help::command_help(command).unwrap_or_default()
        );
        return 0;
    }
    if !args.is_empty() {
        let _ = writeln!(
            io.stderr,
            "ms {command} takes no arguments; use ms version or ms --version"
        );
        return 2;
    }
    let _ = writeln!(io.stdout, "Manuscript {}", crate::VERSION);
    0
}

pub fn run_lsp(args: &[String], io: &mut Io) -> i32 {
    if args.len() != 1 {
        let _ = writeln!(
            io.stderr,
            "ms lsp takes no arguments; it serves the language server on stdin/stdout"
        );
        return 2;
    }
    finish(engine::lsp(io), io)
}

pub fn run_guide(args: &[String], io: &mut Io) -> i32 {
    if args.len() > 1 {
        return usage_error(
            io,
            "ms guide takes no arguments; use 'ms search_symbol' to look symbols up",
        );
    }
    let _ = write!(io.stdout, "{}", ms_tooling::guide::cheatsheet());
    0
}

pub fn run_explain(args: &[String], io: &mut Io) -> i32 {
    let mut json = false;
    let mut codes: Vec<&str> = Vec::new();
    for arg in &args[1..] {
        if matches!(arg.as_str(), "-h" | "--help") {
            return run_help(&["explain".to_string()], io);
        }
        match arg.as_str() {
            "--json" => json = true,
            code => codes.push(code),
        }
    }
    if codes.is_empty() {
        let list: Vec<&str> = ms_syntax::diag::CODES.iter().map(|c| c.code).collect();
        return usage_error(
            io,
            format!(
                "ms explain needs a diagnostic code; codes: {}",
                list.join(" ")
            ),
        );
    }
    let mut status = 0;
    let mut entries = Vec::new();
    for code in codes {
        let Some(info) = ms_syntax::diag::explain(code) else {
            let _ = writeln!(io.stderr, "ms explain: unknown diagnostic code {code}");
            status = 1;
            continue;
        };
        if json {
            entries.push(
                crate::json::Json::object()
                    .with("code", crate::json::Json::str(info.code))
                    .with("family", crate::json::Json::str(info.family))
                    .with("repair", crate::json::Json::str(info.repair)),
            );
        } else {
            let _ = writeln!(
                io.stdout,
                "{}: {}\n  repair: {}",
                info.code, info.family, info.repair
            );
        }
    }
    if json {
        let document = crate::json::Json::object()
            .with("format", crate::json::Json::int(1))
            .with("codes", crate::json::Json::Arr(entries));
        let _ = writeln!(
            io.stdout,
            "{}",
            document.pretty(crate::json::Escape::GoHtml)
        );
    }
    status
}

pub fn run_search_symbol(args: &[String], io: &mut Io) -> i32 {
    let mut names: Vec<String> = Vec::new();
    let (mut limit, mut json) = (DEFAULT_SYMBOL_LIMIT, false);
    let mut i = 1;
    while i < args.len() {
        let (flag, value, inline) = split_value_option(&args[i], &["--limit"]);
        match flag {
            "--json" => json = true,
            "--limit" => {
                let text = required_value(args, &mut i, value, inline);
                match text.and_then(|t| t.parse::<i64>().ok()).filter(|&n| n >= 1) {
                    Some(n) => limit = (n as usize).min(MAX_SYMBOL_LIMIT),
                    None => {
                        return usage_error(
                            io,
                            "ms search_symbol: --limit needs a positive number, e.g. ms search_symbol Config --limit 3",
                        );
                    }
                }
            }
            _ if flag.starts_with('-') => {
                return usage_error(
                    io,
                    format!(
                        "unknown option {flag} for ms search_symbol; run 'ms help search_symbol' for its options"
                    ),
                );
            }
            _ => names.push(flag.to_string()),
        }
        i += 1;
    }
    finish(
        engine::search_symbol(&SearchSymbolRequest { names, limit, json }, io),
        io,
    )
}

pub fn run_review(args: &[String], io: &mut Io) -> i32 {
    match parse_review(args, io) {
        Ok(request) => finish(engine::review(&request, io), io),
        Err(status) => status,
    }
}

/// Read `ms review`'s options; `Err` carries the status for a problem already reported.
fn parse_review(args: &[String], io: &mut Io) -> Result<ReviewRequest, i32> {
    if args.len() < 2 {
        return Err(usage_error(
            io,
            "ms review: missing the file argument; pass a .ms file or a project ms.toml, e.g. ms review ms.toml",
        ));
    }
    if args[1].starts_with('-') {
        return Err(usage_error(
            io,
            format!(
                "unknown option {} for ms review; run 'ms help review' for its options (put the file first, then options)",
                args[1]
            ),
        ));
    }
    let filename = match resolve_input("review", &args[1]) {
        Ok(filename) => filename,
        Err(message) => {
            let _ = writeln!(io.stderr, "{message}");
            return Err(2);
        }
    };
    let (mut diff, mut format, mut output, mut explain) =
        (String::new(), String::new(), String::new(), String::new());
    let (mut all, mut json) = (false, false);
    let mut i = 2;
    while i < args.len() {
        let (flag, value, inline) = split_value_option(
            &args[i],
            &["--diff", "--format", "--explain", "-o", "--output"],
        );
        match flag {
            "--all" => all = true,
            "--json" => json = true,
            "--diff" | "--format" | "--explain" | "-o" | "--output" => {
                let Some(value) = required_value(args, &mut i, value, inline) else {
                    return Err(usage_error(
                        io,
                        format!("{flag} requires a value; run 'ms help review' for examples"),
                    ));
                };
                match flag {
                    "--diff" => diff = value.to_string(),
                    "--format" => format = value.to_string(),
                    "--explain" => explain = value.to_string(),
                    _ => output = value.to_string(),
                }
            }
            _ => {
                return Err(usage_error(
                    io,
                    format!(
                        "unknown option {} for ms review; run 'ms help review' for its options",
                        args[i]
                    ),
                ));
            }
        }
        i += 1;
    }
    if json && !format.is_empty() {
        return Err(usage_error(
            io,
            "--json and --format cannot be combined; --json is the JSON report",
        ));
    } else if json {
        format = "json".to_string();
    } else if format.is_empty() {
        format = "ascii".to_string();
    } else if format != "ascii" && format != "markdown" {
        return Err(usage_error(
            io,
            format!(
                "unknown --format {} for ms review; use ascii or markdown (--json for JSON)",
                ms_driver::project::quoting::quote(&format)
            ),
        ));
    }
    if !explain.is_empty() && diff.is_empty() {
        return Err(usage_error(
            io,
            "--explain needs --diff; it explains one finding of a diff report, e.g. ms review ms.toml --diff change.patch --explain 1",
        ));
    }
    Ok(ReviewRequest {
        filename,
        diff,
        format,
        output,
        explain,
        all,
    })
}
