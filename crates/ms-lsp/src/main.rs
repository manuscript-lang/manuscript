//! `ms-lsp`: the language server on stdin/stdout. Without `MS_LSP_WORKER` the
//! process supervises a worker copy of itself, so a checker fault restarts the
//! worker instead of ending the editor session.

// Links the msrt_* runtime symbols that the standard-library crates reference.
#[cfg(any(test, windows))]
use ms_rt as _;
use std::process::Command;

fn main() {
    let result = if std::env::var_os("MS_LSP_WORKER").is_some() {
        ms_lsp::serve(std::io::stdin(), std::io::stdout())
    } else {
        ms_lsp::supervise(std::io::stdin(), std::io::stdout(), || {
            let exe = std::env::current_exe().expect("current executable");
            let mut command = Command::new(exe);
            command.env("MS_LSP_WORKER", "1");
            command
        })
    };
    if let Err(message) = result {
        eprintln!("ms-lsp: {message}");
        std::process::exit(1);
    }
}
