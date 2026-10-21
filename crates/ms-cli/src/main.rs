//! The `ms` executable. Engines are linked in here; a command whose engine
//! does not exist yet reports "not yet implemented" and exits with 70.
//!
//! Native builds (`build`, `run`, `test`, `profile`) run on the Rust pipeline.

// Links the msrt_* runtime symbols that the standard-library crates reference.
#[cfg(any(test, windows))]
use ms_rt as _;
use std::io::Write;

use ms_cli::backend::Io;
use ms_cli::engine::RustBackend;
use ms_driver::Native;

/// The checker and lowerer recurse over the syntax tree, and the parser admits
/// expression chains and nesting deeper than the default 8 MiB main stack holds.
/// Stack pages are committed on use, so a large reservation is cheap.
const COMPILER_STACK: usize = 512 << 20;

fn main() {
    let worker = std::thread::Builder::new()
        .name("ms".into())
        .stack_size(COMPILER_STACK)
        .spawn(real_main);
    let status = match worker {
        Ok(handle) => handle.join().unwrap_or(70),
        Err(_) => real_main(),
    };
    std::process::exit(status);
}

fn real_main() -> i32 {
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
    status
}
