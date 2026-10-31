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
    let args: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    // Unlocked: `ms lsp` reads the process stdin from its own thread.
    let mut stdin = std::io::stdin();
    let mut stdout = CommandOutput::new(std::io::BufWriter::new(std::io::stdout().lock()));
    let mut stderr = std::io::stderr().lock();
    let status = {
        let mut io = Io {
            stdin: &mut stdin,
            stdout: &mut stdout,
            stderr: &mut stderr,
        };
        ms_cli::run(&args, &Engine::new(Native), &mut io)
    };
    let status = stdout.finish(&mut stderr, status);
    drop(stdout);
    status
}

/// Keep output failures even when a command ignores a write result, or when a
/// buffered write fails only at the final flush.
struct CommandOutput<W> {
    inner: W,
    failure: Option<String>,
}

impl<W: Write> CommandOutput<W> {
    fn new(inner: W) -> Self {
        Self {
            inner,
            failure: None,
        }
    }

    fn record<T>(&mut self, result: std::io::Result<T>) -> std::io::Result<T> {
        if let Err(error) = &result
            && !matches!(
                error.kind(),
                std::io::ErrorKind::BrokenPipe | std::io::ErrorKind::Interrupted
            )
            && self.failure.is_none()
        {
            self.failure = Some(error.to_string());
        }
        result
    }

    fn finish(&mut self, stderr: &mut impl Write, status: i32) -> i32 {
        while self
            .flush()
            .is_err_and(|error| error.kind() == std::io::ErrorKind::Interrupted)
        {}
        if status != 0 {
            return status;
        }
        let Some(error) = &self.failure else {
            return status;
        };
        let _ = writeln!(
            stderr,
            "ms: cannot write stdout: {error}; check the output destination and re-run"
        );
        1
    }
}

impl<W: Write> Write for CommandOutput<W> {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        let result = self.inner.write(bytes);
        self.record(result)
    }

    fn write_all(&mut self, bytes: &[u8]) -> std::io::Result<()> {
        let result = self.inner.write_all(bytes);
        self.record(result)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        let result = self.inner.flush();
        self.record(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{ErrorKind, Result};

    #[derive(Default)]
    struct Failure {
        write: Option<ErrorKind>,
        flush: Option<ErrorKind>,
        flush_calls: usize,
    }

    impl Write for Failure {
        fn write(&mut self, bytes: &[u8]) -> Result<usize> {
            if let Some(kind) = self.write {
                return Err(kind.into());
            }
            Ok(bytes.len())
        }

        fn flush(&mut self) -> Result<()> {
            self.flush_calls += 1;
            if let Some(kind) = self.flush.take() {
                return Err(kind.into());
            }
            Ok(())
        }
    }

    #[test]
    fn failed_writes_are_kept_even_if_the_final_flush_succeeds() {
        let mut output = CommandOutput::new(Failure {
            write: Some(ErrorKind::Other),
            flush: None,
            ..Default::default()
        });
        assert!(output.write_all(b"output").is_err());
        let mut stderr = Vec::new();
        assert_eq!(output.finish(&mut stderr, 0), 1);
        assert!(
            String::from_utf8(stderr)
                .unwrap()
                .contains("cannot write stdout:")
        );
    }

    #[test]
    fn broken_pipes_and_existing_failures_keep_the_command_status() {
        for (kind, status, expected) in [
            (ErrorKind::BrokenPipe, 0, 0),
            (ErrorKind::BrokenPipe, 9, 9),
            (ErrorKind::Other, 0, 1),
            (ErrorKind::Other, 9, 9),
        ] {
            let mut output = CommandOutput::new(Failure {
                write: None,
                flush: Some(kind),
                ..Default::default()
            });
            let mut stderr = Vec::new();
            assert_eq!(output.finish(&mut stderr, status), expected);
            assert_eq!(stderr.is_empty(), expected != 1);
        }
    }

    #[test]
    fn an_interrupted_final_flush_is_retried() {
        let mut output = CommandOutput::new(Failure {
            write: None,
            flush: Some(ErrorKind::Interrupted),
            ..Default::default()
        });
        let mut stderr = Vec::new();
        assert_eq!(output.finish(&mut stderr, 0), 0);
        assert!(stderr.is_empty());
        assert_eq!(output.inner.flush_calls, 2);
    }

    #[test]
    fn normal_output_is_preserved() {
        let mut output = CommandOutput::new(Vec::new());
        output.write_all(b"output\n").unwrap();
        let mut stderr = Vec::new();
        assert_eq!(output.finish(&mut stderr, 0), 0);
        assert_eq!(output.inner, b"output\n");
        assert!(stderr.is_empty());
    }
}
