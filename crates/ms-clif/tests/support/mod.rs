use std::path::Path;
use std::process::{Command, Output};

/// Compile all fixture C code with the same host ABI and CRT as the linker.
pub fn cc() -> Command {
    let program =
        std::env::var("CC").unwrap_or_else(|_| if cfg!(windows) { "clang" } else { "cc" }.into());
    let mut command = Command::new(program);
    if cfg!(target_os = "linux") {
        // The bundled linker links musl, which has no fortified `*_chk` entry points.
        command.arg("-D_FORTIFY_SOURCE=0");
    }
    if cfg!(windows) {
        command.arg(if cfg!(target_arch = "aarch64") {
            "--target=aarch64-pc-windows-msvc"
        } else {
            "--target=x86_64-pc-windows-msvc"
        });
        command.arg("-fms-runtime-lib=dll");
    }
    command
}

/// Runs a freshly linked executable. The in-process linker holds the output open for writing while
/// other test threads fork, so an immediate exec can meet `ETXTBSY` (a fork child still owns a copy
/// of the descriptor for a moment); retry until it clears.
#[allow(dead_code)] // shared by test crates that do not all run executables
pub fn run_exe(exe: &Path, configure: impl Fn(&mut Command)) -> Output {
    let mut attempts = 0;
    loop {
        let mut command = Command::new(exe);
        configure(&mut command);
        match command.output() {
            Err(e) if e.raw_os_error() == Some(26) && attempts < 200 => {
                attempts += 1;
                std::thread::sleep(std::time::Duration::from_millis(5));
            }
            result => return result.expect("run"),
        }
    }
}
