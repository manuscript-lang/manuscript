//! MIR to executable: optimize, generate Cranelift code, link with the runtime.

use std::path::{Path, PathBuf};

use ms_clif::Options;
use ms_mir::ir::Module;
use ms_mir::opt::{Level, optimize};

/// The native build levels, in the CMake spelling.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Profile {
    Debug,
    Release,
    RelWithDebInfo,
    MinSizeRel,
}

impl Profile {
    fn options(self) -> (Level, Options) {
        let mut options = Options::default();
        let level = match self {
            // Debug keeps every check and skips MIR and Cranelift optimization so
            // locals and line tables stay faithful.
            Profile::Debug => {
                options.opt_level = "none";
                Level::None
            }
            Profile::Release | Profile::RelWithDebInfo => Level::Speed,
            Profile::MinSizeRel => {
                options.opt_level = "speed_and_size";
                Level::Speed
            }
        };
        (level, options)
    }
}

/// The runtime archive named by `MS_RT_LIB`, which replaces the one embedded in `ms`.
pub fn runtime_override() -> Result<Option<PathBuf>, String> {
    let Some(path) = std::env::var_os("MS_RT_LIB") else {
        return Ok(None);
    };
    let path = PathBuf::from(path);
    if path.is_file() {
        Ok(Some(path))
    } else {
        Err(format!(
            "MS_RT_LIB={} does not name a file; point it at a libms_native.a",
            path.display()
        ))
    }
}

/// Optimize `module`, generate code and link the executable at `output`. The
/// executable replaces `output` only when the whole build succeeds.
pub fn build_executable(
    module: &mut Module,
    output: &Path,
    profile: Profile,
    runtime: &Path,
) -> Result<(), String> {
    if let Err(errors) = ms_mir::verify::verify_module(module) {
        let text: Vec<String> = errors.iter().map(|e| e.to_string()).collect();
        return Err(format!(
            "the compiler produced invalid code (this is a Manuscript bug, so report it with the source that triggers it):\n{}",
            text.join("\n")
        ));
    }
    let (level, options) = profile.options();
    optimize(module, level, cfg!(debug_assertions));
    let object = ms_clif::compile(module, &options).map_err(|e| e.to_string())?;

    let directory = output
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let stem = format!(".ms-build-{}", std::process::id());
    let object_path = directory.join(format!("{stem}.o"));
    let staged = directory.join(format!("{stem}.exe"));
    let cleanup = || {
        let _ = std::fs::remove_file(&object_path);
        let _ = std::fs::remove_file(&staged);
        if let Some(companion) = ms_clif::link::debug_companion_path(&staged) {
            let _ = std::fs::remove_dir_all(companion);
        }
    };
    if let Err(error) = std::fs::write(&object_path, object) {
        cleanup();
        return Err(format!("cannot write {}: {error}", object_path.display()));
    }
    let linked = ms_clif::link::link_all(&object_path, &[runtime], &staged);
    let _ = std::fs::remove_file(&object_path);
    if let Err(error) = linked {
        cleanup();
        return Err(error.to_string());
    }
    publish(&staged, output).map_err(|error| {
        cleanup();
        format!("cannot write {}: {error}", output.display())
    })
}

/// Publish the native debug companion together with the staged executable. If
/// replacing the executable fails, restore the previous companion as well.
fn publish(staged: &Path, output: &Path) -> std::io::Result<()> {
    let Some(destination) = ms_clif::link::debug_companion_path(output) else {
        return std::fs::rename(staged, output);
    };
    let companion = ms_clif::link::debug_companion_path(staged).expect("same native platform");
    let has_new = companion.exists();
    if has_new {
        // Adjacent dSYM lookup opens the final executable's basename before
        // checking UUIDs. dsymutil named this resource after the staged file.
        let resources = companion.join("Contents/Resources/DWARF");
        let resource = resources.join(staged.file_name().expect("staged filename"));
        let name = output.file_name().ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "executable needs a filename",
            )
        })?;
        let final_resource = resources.join(name);
        // A previous failed publication may already have normalized this file.
        if resource != final_resource && resource.exists() {
            std::fs::rename(resource, &final_resource)?;
        }
        if !final_resource.is_file() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("missing DWARF resource {}", final_resource.display()),
            ));
        }
    }
    let backup = companion.with_extension("previous.dSYM");
    let previous = destination.exists();
    if previous {
        std::fs::rename(&destination, &backup)?;
    }
    if has_new && let Err(error) = std::fs::rename(&companion, &destination) {
        if previous && let Err(restore) = std::fs::rename(&backup, &destination) {
            return Err(std::io::Error::new(
                error.kind(),
                format!(
                    "{error}; cannot restore previous companion: {restore}; retained at {}",
                    backup.display()
                ),
            ));
        }
        return Err(error);
    }
    if let Err(error) = std::fs::rename(staged, output) {
        let mut failures = Vec::new();
        if has_new && let Err(restore) = std::fs::rename(&destination, &companion) {
            failures.push(format!(
                "cannot recover new companion at {}: {restore}",
                destination.display()
            ));
        }
        if previous && let Err(restore) = std::fs::rename(&backup, &destination) {
            failures.push(format!(
                "cannot restore previous companion: {restore}; retained at {}",
                backup.display()
            ));
        }
        if !failures.is_empty() {
            return Err(std::io::Error::new(
                error.kind(),
                format!("{error}; {}", failures.join("; ")),
            ));
        }
        return Err(error);
    }
    if previous {
        let _ = std::fs::remove_dir_all(backup);
    }
    Ok(())
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    #[test]
    fn publication_without_debug_lines_retires_old_companion() {
        let root =
            std::env::temp_dir().join(format!("ms-driver-debug-retire-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let staged = root.join("stage");
        let output = root.join("output");
        std::fs::write(&staged, "new executable").unwrap();
        std::fs::write(&output, "old executable").unwrap();
        let old = ms_clif::link::debug_companion_path(&output).unwrap();
        std::fs::create_dir_all(&old).unwrap();
        std::fs::write(old.join("data"), "old").unwrap();
        super::publish(&staged, &output).unwrap();
        assert_eq!(std::fs::read_to_string(&output).unwrap(), "new executable");
        assert!(!old.exists());
        assert_eq!(std::fs::read_dir(&root).unwrap().count(), 1);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn failed_binary_publication_restores_debug_companion() {
        let root =
            std::env::temp_dir().join(format!("ms-driver-debug-rollback-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let staged = root.join("stage");
        let output = root.join("output");
        std::fs::write(&staged, "new executable").unwrap();
        std::fs::create_dir_all(&output).unwrap(); // file rename must fail
        let new = ms_clif::link::debug_companion_path(&staged).unwrap();
        let old = ms_clif::link::debug_companion_path(&output).unwrap();
        let resources = new.join("Contents/Resources/DWARF");
        std::fs::create_dir_all(&resources).unwrap();
        std::fs::create_dir_all(&old).unwrap();
        std::fs::write(resources.join("stage"), "new").unwrap();
        std::fs::write(old.join("data"), "old").unwrap();
        assert!(super::publish(&staged, &output).is_err());
        assert_eq!(std::fs::read_to_string(old.join("data")).unwrap(), "old");
        assert_eq!(
            std::fs::read_to_string(resources.join("output")).unwrap(),
            "new"
        );
        assert!(staged.exists());
        // Recovery leaves a staged companion that can be published again.
        std::fs::remove_dir(&output).unwrap();
        super::publish(&staged, &output).unwrap();
        assert_eq!(
            std::fs::read_to_string(old.join("Contents/Resources/DWARF/output")).unwrap(),
            "new"
        );
        assert!(!staged.exists());
        assert_eq!(std::fs::read_to_string(&output).unwrap(), "new executable");
        std::fs::remove_dir_all(root).unwrap();
    }
}
