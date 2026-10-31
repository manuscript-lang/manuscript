//! The `ms` executable.
//!
//! Native builds (`build`, `run`, `test`, `profile`) run on the Rust pipeline.

// Links the msrt_* runtime symbols that the standard-library crates reference.
#[cfg(test)]
use ms_rt as _;
use std::io::Write;

use ms_build::Native;
use ms_cli::backend::Io;
use ms_cli::engine::Engine;

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
    let args: Result<Vec<String>, _> = std::env::args_os()
        .skip(1)
        .map(|a| a.into_string())
        .collect();
    // Unlocked: `ms lsp` reads the process stdin from its own thread.
    let mut stdin = std::io::stdin();
    let mut stdout = std::io::BufWriter::new(std::io::stdout().lock());
    let mut stderr = std::io::stderr().lock();
    let args = match args {
        Ok(args) => args,
        Err(_) => {
            let _ = writeln!(
                stderr,
                "ms: an argument is not valid UTF-8; pass UTF-8 command-line arguments"
            );
            return 2;
        }
    };
    let status = {
        let mut io = Io {
            stdin: &mut stdin,
            stdout: &mut stdout,
            stderr: &mut stderr,
        };
        ms_cli::run(&args, &Engine::new(Native), &mut io)
    };
    let _ = stdout.flush();
    drop(stdout);
    status
}
