//! The `ms` executable. Engines are linked in here; until they exist every
//! command that needs one reports "not yet implemented" and exits with 70.

use std::io::Write;

use ms_cli::backend::{Io, NoEngines};

fn main() {
    let args: Vec<String> = std::env::args_os().skip(1).map(|a| a.to_string_lossy().into_owned()).collect();
    let stdin = std::io::stdin();
    let mut stdin = stdin.lock();
    let mut stdout = std::io::BufWriter::new(std::io::stdout().lock());
    let mut stderr = std::io::stderr().lock();
    let status = {
        let mut io = Io { stdin: &mut stdin, stdout: &mut stdout, stderr: &mut stderr };
        ms_cli::run(&args, &NoEngines, &mut io)
    };
    let _ = stdout.flush();
    drop(stdout);
    std::process::exit(status);
}
