//! Help text. The strings in [`crate::help_text`] were generated from the Go
//! `ms help` output and edited only where the Rust implementation differs
//! (no Go toolchain, no debugger, redefined `ms profile`).

use crate::help_text as t;
pub use crate::help_text::HELP;

/// Every dispatched command, in help order. A test keeps it equal to the help text.
pub const COMMAND_NAMES: &[&str] = &[
    "check",
    "lint",
    "build",
    "emit",
    "run",
    "test",
    "fmt",
    "verify",
    "inspect",
    "diagram",
    "review",
    "profile",
    "init",
    "lsp",
    "search_symbol",
    "guide",
    "help",
    "version",
];

/// `ms help <command>` text, or `None` for an unknown command.
pub fn command_help(command: &str) -> Option<String> {
    let text = match command {
        "check" => t::HELP_CHECK,
        "lint" => t::HELP_LINT,
        "build" => t::HELP_BUILD,
        "emit" => t::HELP_EMIT,
        "run" => t::HELP_RUN,
        "test" => t::HELP_TEST,
        "fmt" => t::HELP_FMT,
        "verify" => t::HELP_VERIFY,
        "inspect" => t::HELP_INSPECT,
        "diagram" => t::HELP_DIAGRAM,
        "review" => t::HELP_REVIEW,
        "profile" => crate::profile::HELP,
        "init" => t::HELP_INIT,
        "lsp" => t::HELP_LSP,
        "search_symbol" => t::HELP_SEARCH_SYMBOL,
        "guide" => t::HELP_GUIDE,
        "help" => t::HELP_HELP,
        "version" => t::HELP_VERSION,
        _ => return None,
    };
    Some(text.to_string())
}
