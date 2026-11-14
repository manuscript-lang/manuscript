//! Linker driver. Every platform runs the `lld` bundled in `ms` (Linux over glibc 2.28 stubs, or musl with `--static`, macOS over generated
//! SDK stubs, Windows over the mingw-w64 CRT), so no C toolchain or SDK is involved.

use crate::{BuildOptions, Error};
use std::path::{Path, PathBuf};

mod bundled;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod fetch;
mod lld;
pub use bundled::RUNTIME_HOT_IR;
pub use lld::{is_static, llvm_tools};

/// Links `object` and the runtime inputs (objects or static libraries), in order, into the executable `out`.
pub fn link_all(object: &Path, inputs: &[&Path], out: &Path) -> Result<(), Error> {
    link_with(object, inputs, out, false, &BuildOptions::default())
}

/// Like [`link_all`]; `strip` also drops the symbol table (smallest executable, no symbol names
/// for profilers or backtraces). `build.static_musl` links static musl instead of glibc 2.28 stubs,
/// and the runtime in `inputs` must be the build for that libc.
pub fn link_with(
    object: &Path,
    inputs: &[&Path],
    out: &Path,
    strip: bool,
    build: &BuildOptions,
) -> Result<(), Error> {
    lld::link(object, inputs, out, strip, build)?;
    place_executable(out)?;
    emit_debug_companion(object, inputs, out)
}

/// Native debug companion for an executable, where the platform uses one.
/// macOS source lines live in this dSYM bundle after object files are removed.
pub fn debug_companion_path(output: &Path) -> Option<PathBuf> {
    if !cfg!(target_os = "macos") {
        return None;
    }
    let mut path = output.as_os_str().to_owned();
    path.push(".dSYM");
    Some(path.into())
}

#[cfg(not(target_os = "macos"))]
fn emit_debug_companion(_object: &Path, _inputs: &[&Path], _out: &Path) -> Result<(), Error> {
    Ok(())
}

#[cfg(target_os = "macos")]
fn emit_debug_companion(object: &Path, inputs: &[&Path], out: &Path) -> Result<(), Error> {
    use cranelift_object::object::Object as _;
    // Any object among the inputs may carry the DWARF (LLVM's does when it compiled the functions).
    let mut has_dwarf = false;
    for path in std::iter::once(object).chain(
        inputs
            .iter()
            .copied()
            .filter(|p| p.extension().is_some_and(|e| e == "o")),
    ) {
        let bytes = std::fs::read(path).map_err(|e| Error(format!("read debug object: {e}")))?;
        let file = cranelift_object::object::File::parse(bytes.as_slice())
            .map_err(|e| Error(format!("read debug object: {e}")))?;
        has_dwarf |= file.section_by_name("__debug_info").is_some();
    }
    if !has_dwarf {
        return Ok(());
    }
    let companion = debug_companion_path(out).expect("macOS companion");
    let tool = "dsymutil";
    let o = debug_companion_command(object, out, &companion)
        .map_err(|e| Error(format!("cannot resolve debug companion paths: {e}")))?
        .output();
    // Without `dsymutil` (no Xcode tools) the executable still runs; it just has no source lines.
    let o = match o {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        other => other.map_err(|e| Error(format!("cannot run {tool}: {e}")))?,
    };
    if !o.status.success() {
        return Err(Error(format!(
            "{tool} failed: {}",
            String::from_utf8_lossy(&o.stderr)
        )));
    }
    if !companion.is_dir() {
        return Err(Error("dsymutil did not produce a debug companion".into()));
    }
    Ok(())
}

// Keep the linker and debug consumer on the same absolute path spelling. In
// particular, do not canonicalize symlinks or `..` differently from the linker.
#[cfg(any(target_os = "macos", test))]
fn macos_debug_arguments(
    command: &mut std::process::Command,
    object: &Path,
    inputs: &[&Path],
    out: &Path,
) -> std::io::Result<()> {
    let object = std::path::absolute(object)?;
    let mut prefix = object
        .parent()
        .expect("absolute object parent")
        .to_path_buf();
    // Include the directory boundary: leave relative names, not `/program.o`,
    // and never strip a similarly named sibling such as `stage-external`.
    prefix.push("");
    command
        .arg("-oso_prefix")
        .arg(prefix)
        .arg("-o")
        .arg(std::path::absolute(out)?);
    command.arg(object);
    for input in inputs {
        command.arg(std::path::absolute(input)?);
    }
    Ok(())
}

#[cfg(any(target_os = "macos", test))]
fn debug_companion_command(
    object: &Path,
    out: &Path,
    companion: &Path,
) -> std::io::Result<std::process::Command> {
    let object = std::path::absolute(object)?;
    let mut command = std::process::Command::new("dsymutil");
    // Only stage-owned N_OSO names are relative. A global prepend would also
    // rebase caller-owned absolute objects and silently lose their DWARF.
    command
        .current_dir(object.parent().expect("absolute object parent"))
        .arg(std::path::absolute(out)?)
        .arg("-o")
        .arg(std::path::absolute(companion)?);
    Ok(command)
}

/// Windows linkers add `.exe` to an output name without it; the build keeps the name it chose.
fn place_executable(out: &Path) -> Result<(), Error> {
    if out.exists() || out.extension().is_some() {
        return Ok(());
    }
    let mut with_suffix = out.as_os_str().to_owned();
    with_suffix.push(".exe");
    if Path::new(&with_suffix).exists() {
        std::fs::rename(&with_suffix, out)
            .map_err(|e| Error(format!("cannot place the executable: {e}")))?;
    }
    Ok(())
}

#[cfg(test)]
mod debug_command_tests {
    use super::*;
    use std::ffi::OsString;
    use std::process::Command;

    fn arguments(command: &Command) -> Vec<OsString> {
        command.get_args().map(OsString::from).collect()
    }

    fn check_paths(object: &Path, external: &Path, output: &Path) {
        let before = std::env::current_dir().unwrap();
        let absolute_object = std::path::absolute(object).unwrap();
        let stage = absolute_object.parent().unwrap();
        let mut prefix = stage.to_path_buf();
        prefix.push("");
        let mut linker = Command::new("lld");
        macos_debug_arguments(&mut linker, object, &[external], output).unwrap();
        assert_eq!(
            arguments(&linker),
            vec![
                OsString::from("-oso_prefix"),
                prefix.into_os_string(),
                OsString::from("-o"),
                std::path::absolute(output).unwrap().into_os_string(),
                absolute_object.as_os_str().to_owned(),
                std::path::absolute(external).unwrap().into_os_string(),
            ]
        );
        let mut bundle = output.as_os_str().to_owned();
        bundle.push(".dSYM");
        let debug = debug_companion_command(object, output, Path::new(&bundle)).unwrap();
        assert_eq!(debug.get_program(), "dsymutil");
        assert_eq!(debug.get_current_dir(), Some(stage));
        assert_eq!(
            arguments(&debug),
            vec![
                std::path::absolute(output).unwrap().into_os_string(),
                OsString::from("-o"),
                std::path::absolute(Path::new(&bundle))
                    .unwrap()
                    .into_os_string(),
            ]
        );
        assert_eq!(std::env::current_dir().unwrap(), before);
    }

    #[test]
    fn staged_debug_paths_preserve_spaces_and_external_directory_boundaries() {
        let base = std::env::current_dir().unwrap().join("debug fixtures");
        let stage = base.join("stage with spaces");
        let external = base.join("stage with spaces-external/runtime.o");
        check_paths(
            &stage.join("program.o"),
            &external,
            &base.join("output/program"),
        );
        let mut prefix = stage.into_os_string();
        prefix.push(std::path::MAIN_SEPARATOR_STR);
        assert!(
            !external
                .as_os_str()
                .as_encoded_bytes()
                .starts_with(prefix.as_encoded_bytes())
        );
    }

    #[test]
    fn relative_debug_paths_are_absolute_before_the_child_changes_directory() {
        for object in [
            "program.o",
            "./nested/stage/program.o",
            "nested//./stage/program.o",
            "../stage with spaces/program.o",
        ] {
            check_paths(
                Path::new(object),
                Path::new("./external/runtime.o"),
                Path::new("./output with spaces/program"),
            );
        }
    }
}
