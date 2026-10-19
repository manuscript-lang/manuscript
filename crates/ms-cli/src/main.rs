//! The `ms` executable. Engines are linked in here; a command whose engine
//! does not exist yet reports "not yet implemented" and exits with 70.
//!
//! Native builds (`build`, `run`, `test`, `profile`) run on the Rust pipeline.

use std::io::Write;

use ms_cli::backend::Io;
use ms_cli::engine::RustBackend;
use ms_driver::Native;

fn main() {
    let args: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    // Unlocked: `ms lsp` reads the process stdin from its own thread.
    let mut stdin = std::io::stdin();
    let mut stdout = std::io::BufWriter::new(std::io::stdout().lock());
    let mut stderr = std::io::stderr().lock();
    let status = {
        let mut io = Io {
            stdin: &mut stdin,
            stdout: &mut stdout,
            stderr: &mut stderr,
        };
        ms_cli::run(&args, &RustBackend::new(Native), &mut io)
    };
    let _ = stdout.flush();
    drop(stdout);
    std::process::exit(status);
}
