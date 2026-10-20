use std::process::Command;

/// Compile all fixture C code with the same host ABI and CRT as the linker.
pub fn cc() -> Command {
    let program =
        std::env::var("CC").unwrap_or_else(|_| if cfg!(windows) { "clang" } else { "cc" }.into());
    let mut command = Command::new(program);
    if cfg!(windows) {
        command.arg(format!("--target={}", target_lexicon::HOST));
        command.arg("-fms-runtime-lib=dll");
    }
    command
}
