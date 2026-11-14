//! MIR to executable: optimize, generate Cranelift code, link with the runtime.

use std::path::{Path, PathBuf};

use ms_clif::{BuildOptions, CopyProbe, Options};
use ms_mir::ir::Module;
use ms_mir::opt::{Level, optimize};

/// An exclusively owned temporary directory beside the final executable.
/// Callers remove their artifacts; dropping this guard removes only an empty directory,
/// preserving any recovery backup that publication deliberately retained.
pub struct BuildStage {
    directory: PathBuf,
}

impl BuildStage {
    /// Allocate a fresh directory on the output's filesystem without reusing stale paths.
    pub fn create(parent: &Path) -> std::io::Result<Self> {
        use std::sync::atomic::AtomicUsize;
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        Self::create_with(parent, &NEXT)
    }

    /// Allocate beside `output` without occupying an alias of the requested executable name.
    pub fn for_output(output: &Path) -> std::io::Result<Self> {
        let parent = output
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
            .unwrap_or(Path::new("."));
        loop {
            let candidate = Self::create(parent)?;
            let aliases_output = output.is_dir()
                && std::fs::canonicalize(output)
                    .ok()
                    .and_then(|output| {
                        std::fs::canonicalize(candidate.path())
                            .ok()
                            .map(|stage| output == stage)
                    })
                    .unwrap_or(false);
            if !aliases_output {
                return Ok(candidate);
            }
        }
    }

    fn create_with(parent: &Path, next: &std::sync::atomic::AtomicUsize) -> std::io::Result<Self> {
        use std::sync::atomic::Ordering;
        std::fs::create_dir_all(parent)?;
        loop {
            let directory = parent.join(format!(
                ".ms-build-{}-{}",
                std::process::id(),
                next.fetch_add(1, Ordering::Relaxed)
            ));
            match std::fs::create_dir(&directory) {
                Ok(()) => return Ok(Self { directory }),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
    }

    /// The owned directory in which a caller writes its temporary artifacts.
    pub fn path(&self) -> &Path {
        &self.directory
    }
}

impl Drop for BuildStage {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir(&self.directory);
    }
}

/// The native build levels, in the CMake spelling.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Profile {
    Debug,
    Release,
    MinSizeRel,
}

/// The backend selected for the program's functions. LLVM builds still use
/// Cranelift for data, descriptors and the native entry point.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Backend {
    Cranelift,
    Llvm,
}

impl Backend {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Cranelift => "cranelift",
            Self::Llvm => "llvm",
        }
    }

    pub(crate) fn parse(text: &str) -> Option<Self> {
        match text {
            "cranelift" => Some(Self::Cranelift),
            "llvm" => Some(Self::Llvm),
            _ => None,
        }
    }
}

impl Profile {
    fn options(self, build: &BuildOptions) -> (Level, Options, Option<&'static str>) {
        let mut options = Options {
            build: build.clone(),
            ..Options::default()
        };
        let mut llvm = None;
        let level = match self {
            // Debug keeps every check and skips MIR and Cranelift optimization so
            // locals and line tables stay faithful.
            Profile::Debug => {
                options.opt_level = "none";
                Level::None
            }
            Profile::Release => {
                llvm = llvm_level(build, "3");
                Level::Speed
            }
            Profile::MinSizeRel => {
                options.opt_level = "speed_and_size";
                llvm = llvm_level(build, "s");
                Level::Speed
            }
        };
        (level, options, llvm)
    }
}

/// LLVM optimization for release builds: used when the LLVM tools can be fetched (or are named by
/// `build.llvm_tools`) and `build.cranelift_only` is off; otherwise release builds fall back to
/// Cranelift.
fn llvm_level(build: &BuildOptions, level: &'static str) -> Option<&'static str> {
    if build.cranelift_only {
        return None;
    }
    crate::llvm::available(build).then_some(level)
}

/// Native inputs beyond the explicit link files: the selected runtime archive.
/// The caller resolves runtime precedence before forming this inventory.
pub fn native_inputs(_build: &BuildOptions, runtime: &Path) -> Vec<PathBuf> {
    vec![runtime.to_path_buf()]
}

/// The backend currently available for `profile`. For an existing artifact, use
/// the backend returned by `build_executable` or retained in its cache entry.
pub fn backend_name(profile: Profile, build: &BuildOptions) -> &'static str {
    let llvm = match profile {
        Profile::Debug => None,
        Profile::Release | Profile::MinSizeRel => llvm_level(build, "3"),
    };
    if llvm.is_some() { "llvm" } else { "cranelift" }
}

/// The runtime archive named by `build.runtime` (`MS_RT_LIB`), which replaces the one embedded in `ms`.
pub fn runtime_override(build: &BuildOptions) -> Result<Option<PathBuf>, String> {
    let Some(path) = &build.runtime else {
        return Ok(None);
    };
    if path.is_file() {
        Ok(Some(path.clone()))
    } else {
        Err(format!(
            "MS_RT_LIB={} does not name a file; point it at a libms_native.a",
            path.display()
        ))
    }
}

/// Re-verifies `module` after the pass `name`, which must keep it valid.
fn verify_after(module: &Module, name: &str) -> Result<(), String> {
    ms_mir::verify::verify_module(module).map_err(|errors| {
        let text: Vec<String> = errors.iter().map(|e| e.to_string()).collect();
        format!(
            "the {name} pass produced invalid code (this is a Manuscript bug):\n{}",
            text.join("\n")
        )
    })
}

/// Reports or rejects the copies of object values in `module` (`MS_COPY_PROBE`,
/// `MS_COPY_PROBE=strict`): one-owner lowering duplicates an object only through `.clone()`.
fn probe_copies(module: &Module, probe: CopyProbe) -> Result<(), String> {
    if probe == CopyProbe::Off {
        return Ok(());
    }
    let sites = ms_mir::copies::object_copies(module);
    if probe == CopyProbe::Report {
        for s in &sites {
            eprintln!("copy-probe\t{s}");
        }
        return Ok(());
    }
    if sites.is_empty() {
        return Ok(());
    }
    let text: Vec<String> = sites.iter().map(|s| s.to_string()).collect();
    Err(format!(
        "the lowered code copies {} object value(s), which have one owner (this is a Manuscript bug: lowering must move the value or call its clone):\n{}",
        sites.len(),
        text.join("\n")
    ))
}

/// Optimize `module`, generate code and link the executable at `output`. The
/// executable replaces `output` only when the whole build succeeds.
pub fn build_executable(
    module: &mut Module,
    output: &Path,
    profile: Profile,
    runtime: &Path,
    extra: &[PathBuf],
    build: &BuildOptions,
) -> Result<Backend, String> {
    build_executable_pinned(module, output, profile, runtime, extra, build, None)
}

/// `build_executable` that also leaves this build's own executable at `pin` before it
/// replaces `output`. Another build can replace `output` at any moment afterwards, so a
/// caller that must read back exactly what this build produced reads `pin`.
/// On macOS the matching debug companion is copied beside `pin` before publication.
/// The caller owns `pin` and its companion; a reused pin replaces both, including
/// removing a previous companion when this build has none.
pub fn build_executable_pinned(
    module: &mut Module,
    output: &Path,
    profile: Profile,
    runtime: &Path,
    extra: &[PathBuf],
    build: &BuildOptions,
    pin: Option<&Path>,
) -> Result<Backend, String> {
    if let Some(missing) = extra.iter().find(|p| !p.is_file()) {
        return Err(format!(
            "--link {} does not name a file; pass an object (.o) or static library (.a)",
            missing.display()
        ));
    }
    if let Err(errors) = ms_mir::verify::verify_module(module) {
        let text: Vec<String> = errors.iter().map(|e| e.to_string()).collect();
        return Err(format!(
            "the compiler produced invalid code (this is a Manuscript bug, so report it with the source that triggers it):\n{}",
            text.join("\n")
        ));
    }
    probe_copies(module, build.copy_probe)?;
    let timings = build.timings;
    let started = std::time::Instant::now();
    let phase = |name: &str| {
        if timings {
            eprintln!(
                "ms-timings: {name} done at {:.3}s",
                started.elapsed().as_secs_f64()
            );
        }
    };
    let (level, options, llvm) = profile.options(build);
    let backend = if llvm.is_some() {
        Backend::Llvm
    } else {
        Backend::Cranelift
    };
    optimize(module, level, cfg!(debug_assertions));
    // Not an optimization: it keeps cancellation from leaking, so every profile runs it.
    let unwound = ms_mir::unwind::run(module);
    if unwound && cfg!(debug_assertions) {
        verify_after(module, "unwind")?;
    }
    phase("mir optimize");
    let compiled = match llvm {
        Some(level) => crate::llvm::compile(module, options.checks, level, build),
        None => ms_clif::compile(module, &options).map(|object| vec![object]),
    };
    let mut objects = compiled.map_err(|e| {
        format!(
            "native code generation failed (this is a Manuscript bug, so report it with the source that triggers it; 'ms emit <file>' prints the lowered code): {e}"
        )
    })?;
    // The first object is the main one; the rest link beside it, ahead of the runtime.
    let first = objects.remove(0);

    phase("codegen");
    let directory = output
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let stage = BuildStage::for_output(output).map_err(|error| {
        format!(
            "cannot create build staging directory in {}: {error}",
            directory.display()
        )
    })?;
    let object_path = stage.path().join("program.o");
    let llvm_paths: Vec<PathBuf> = (0..objects.len())
        .map(|k| stage.path().join(format!("program.llvm{k}.o")))
        .collect();
    let staged = stage.path().join("program.exe");
    let cleanup = || {
        let _ = std::fs::remove_file(&object_path);
        for path in &llvm_paths {
            let _ = std::fs::remove_file(path);
        }
        let _ = std::fs::remove_file(&staged);
        if let Some(companion) = ms_clif::link::debug_companion_path(&staged) {
            let _ = std::fs::remove_dir_all(companion);
        }
    };
    if let Err(error) = std::fs::write(&object_path, first) {
        cleanup();
        return Err(format!("cannot write {}: {error}", object_path.display()));
    }
    // The functions LLVM compiled link beside the Cranelift object, ahead of the runtime.
    let mut inputs: Vec<&Path> = extra.iter().map(PathBuf::as_path).collect();
    inputs.push(runtime);
    for (k, (path, llvm)) in llvm_paths.iter().zip(&objects).enumerate() {
        if let Err(error) = std::fs::write(path, llvm) {
            cleanup();
            return Err(format!("cannot write {}: {error}", path.display()));
        }
        inputs.insert(k, path);
    }
    let linked = ms_clif::link::link_with(
        &object_path,
        &inputs,
        &staged,
        profile == Profile::MinSizeRel,
        build,
    );
    phase("link");
    let _ = std::fs::remove_file(&object_path);
    for path in &llvm_paths {
        let _ = std::fs::remove_file(path);
    }
    if let Err(error) = linked {
        cleanup();
        return Err(error.to_string());
    }
    if let Some(pin) = pin
        && let Err(error) = pin_artifacts(&staged, pin)
    {
        cleanup();
        return Err(format!("cannot write {}: {error}", pin.display()));
    }
    publish(&staged, output).map_err(|error| {
        cleanup();
        format!("cannot write {}: {error}", output.display())
    })?;
    Ok(backend)
}

/// Capture from the exclusively owned producer, never from the public output.
fn pin_artifacts(staged: &Path, pin: &Path) -> std::io::Result<()> {
    let companion = ms_clif::link::debug_companion_path(staged);
    let destination = ms_clif::link::debug_companion_path(pin);
    pin_artifacts_with(staged, pin, companion.as_deref(), destination.as_deref())
}

fn pin_artifacts_with(
    staged: &Path,
    pin: &Path,
    companion: Option<&Path>,
    destination: Option<&Path>,
) -> std::io::Result<()> {
    let _ = std::fs::remove_file(pin);
    // A caller can reuse a pin after a build with debug information. Absence in
    // this producer must not leave the previous producer's companion attached.
    if let Some(destination) = destination
        && destination.try_exists()?
    {
        std::fs::remove_dir_all(destination)?;
    }
    let captured = (|| {
        std::fs::hard_link(staged, pin).or_else(|_| std::fs::copy(staged, pin).map(|_| ()))?;
        if let (Some(companion), Some(destination)) = (companion, destination)
            && companion.try_exists()?
        {
            crate::cache::copy_tree(companion, destination)?;
            normalize_debug_resource(destination, staged, pin)?;
        }
        Ok(())
    })();
    if captured.is_err() {
        let _ = std::fs::remove_file(pin);
        if let Some(destination) = destination {
            let _ = std::fs::remove_dir_all(destination);
        }
    }
    captured
}

/// Adjacent dSYM lookup checks the executable basename before checking UUIDs.
fn normalize_debug_resource(companion: &Path, staged: &Path, output: &Path) -> std::io::Result<()> {
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
    Ok(())
}

#[cfg(test)]
mod pin_tests {
    use super::*;

    struct Fixture(PathBuf);
    impl Fixture {
        fn new(name: &str) -> Self {
            let root = std::env::temp_dir().join(format!("ms-pin-{name}-{}", std::process::id()));
            std::fs::create_dir(&root).unwrap();
            Self(root)
        }
        fn bundle(&self, name: &str, resource: &str, bytes: &[u8]) -> PathBuf {
            let bundle = self.0.join(name);
            let dwarf = bundle.join("Contents/Resources/DWARF");
            std::fs::create_dir_all(&dwarf).unwrap();
            std::fs::write(dwarf.join(resource), bytes).unwrap();
            bundle
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn pinned_companion_keeps_producer_bytes_and_normalizes_resource_name() {
        let fixture = Fixture::new("identity");
        let staged = fixture.0.join("producer");
        let pin = fixture.0.join("pinned");
        std::fs::write(&staged, b"executable A").unwrap();
        let companion = fixture.bundle("producer.dSYM", "producer", b"debug A UUID A");
        let destination = fixture.0.join("pinned.dSYM");
        pin_artifacts_with(&staged, &pin, Some(&companion), Some(&destination)).unwrap();
        // A later producer replaces the public bundle; the pin is a deep copy.
        std::fs::write(
            companion.join("Contents/Resources/DWARF/producer"),
            b"debug B UUID B",
        )
        .unwrap();
        assert_eq!(
            std::fs::read(destination.join("Contents/Resources/DWARF/pinned")).unwrap(),
            b"debug A UUID A"
        );
        assert!(
            !destination
                .join("Contents/Resources/DWARF/producer")
                .exists()
        );
        assert_eq!(std::fs::read(pin).unwrap(), b"executable A");
    }

    #[test]
    fn reused_pin_replaces_companion_and_represents_absence() {
        let fixture = Fixture::new("reuse");
        let staged = fixture.0.join("producer");
        let pin = fixture.0.join("pinned");
        let companion = fixture.bundle("producer.dSYM", "producer", b"debug A");
        let destination = fixture.0.join("pinned.dSYM");
        std::fs::write(&staged, b"A").unwrap();
        pin_artifacts_with(&staged, &pin, Some(&companion), Some(&destination)).unwrap();
        // Replacement changes the inode, as a completed native build does.
        std::fs::remove_file(&staged).unwrap();
        std::fs::write(&staged, b"B").unwrap();
        std::fs::remove_dir_all(&companion).unwrap();
        pin_artifacts_with(&staged, &pin, Some(&companion), Some(&destination)).unwrap();
        assert_eq!(std::fs::read(&pin).unwrap(), b"B");
        assert!(!destination.exists());
        fixture.bundle("producer.dSYM", "producer", b"debug C");
        pin_artifacts_with(&staged, &pin, Some(&companion), Some(&destination)).unwrap();
        assert_eq!(
            std::fs::read(destination.join("Contents/Resources/DWARF/pinned")).unwrap(),
            b"debug C"
        );
    }

    #[test]
    fn malformed_companion_removes_partial_pin_without_touching_producer() {
        let fixture = Fixture::new("capture-error");
        let staged = fixture.0.join("producer");
        let pin = fixture.0.join("pinned");
        std::fs::write(&staged, b"new executable").unwrap();
        let companion = fixture.bundle("producer.dSYM", "wrong", b"new debug");
        let destination = fixture.0.join("pinned.dSYM");
        assert!(pin_artifacts_with(&staged, &pin, Some(&companion), Some(&destination)).is_err());
        assert!(!pin.exists());
        assert!(!destination.exists());
        assert_eq!(std::fs::read(staged).unwrap(), b"new executable");
        assert_eq!(
            std::fs::read(companion.join("Contents/Resources/DWARF/wrong")).unwrap(),
            b"new debug"
        );
    }
}

/// Publish the native debug companion together with the staged executable. If
/// replacing the executable fails, restore the previous companion as well.
pub fn publish(staged: &Path, output: &Path) -> std::io::Result<()> {
    let Some(destination) = ms_clif::link::debug_companion_path(output) else {
        return std::fs::rename(staged, output);
    };
    let companion = ms_clif::link::debug_companion_path(staged).expect("same native platform");
    let has_new = companion.exists();
    if has_new {
        normalize_debug_resource(&companion, staged, output)?;
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
            std::env::temp_dir().join(format!("ms-build-debug-retire-{}", std::process::id()));
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
            std::env::temp_dir().join(format!("ms-build-debug-rollback-{}", std::process::id()));
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

#[cfg(test)]
mod stage_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct Scratch(PathBuf);

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn scratch(name: &str) -> Scratch {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        loop {
            let path = std::env::temp_dir().join(format!(
                "ms-native-stage-{name}-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            match std::fs::create_dir(&path) {
                Ok(()) => return Scratch(path),
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => panic!("cannot create test directory: {error}"),
            }
        }
    }

    fn candidate(parent: &Path, counter: usize) -> PathBuf {
        parent.join(format!(".ms-build-{}-{counter}", std::process::id()))
    }

    #[test]
    fn build_stages_skip_stale_files_and_directories() {
        let root = scratch("stale");
        let parent = &root.0;
        let next = AtomicUsize::new(0);
        std::fs::create_dir(candidate(parent, 0)).unwrap();
        std::fs::write(candidate(parent, 0).join("retained"), b"old stage").unwrap();
        let sentinel = parent.join("sentinel");
        std::fs::write(&sentinel, b"original bytes").unwrap();
        std::fs::hard_link(&sentinel, candidate(parent, 1)).unwrap();
        let stage = BuildStage::create_with(parent, &next).unwrap();
        assert_eq!(stage.path(), candidate(parent, 2));
        assert_eq!(next.load(Ordering::Relaxed), 3);
        assert_eq!(
            std::fs::read(candidate(parent, 0).join("retained")).unwrap(),
            b"old stage"
        );
        assert_eq!(
            std::fs::read(candidate(parent, 1)).unwrap(),
            b"original bytes"
        );
        assert_eq!(std::fs::read(sentinel).unwrap(), b"original bytes");
        drop(stage);
        assert!(!candidate(parent, 2).exists());
        assert!(candidate(parent, 0).is_dir());
        assert!(candidate(parent, 1).is_file());
    }

    #[test]
    fn build_stage_creates_missing_output_parents() {
        let root = scratch("missing-parent");
        let parent = root.0.join("nested/output");
        let stage = BuildStage::create(&parent).unwrap();
        let path = stage.path().to_owned();
        assert!(path.is_dir());
        drop(stage);
        assert!(parent.is_dir());
        assert!(!path.exists());
    }

    #[test]
    fn build_stage_drop_preserves_retained_recovery_resources() {
        let root = scratch("recovery");
        let stage = BuildStage::create(&root.0).unwrap();
        let path = stage.path().to_owned();
        let backup = path.join("program.exe.previous.dSYM");
        std::fs::create_dir(&backup).unwrap();
        std::fs::write(backup.join("resource"), b"previous debug resource").unwrap();
        drop(stage);
        assert!(path.is_dir());
        assert_eq!(
            std::fs::read(backup.join("resource")).unwrap(),
            b"previous debug resource"
        );
    }

    #[test]
    fn concurrent_build_stages_are_distinct_and_remove_empty_directories() {
        let root = scratch("concurrent");
        let next = AtomicUsize::new(0);
        let ready = std::sync::Barrier::new(9);
        let finish = std::sync::Barrier::new(9);
        std::thread::scope(|scope| {
            let handles: Vec<_> = (0..8)
                .map(|_| {
                    scope.spawn(|| {
                        let stage = BuildStage::create_with(&root.0, &next);
                        ready.wait();
                        finish.wait();
                        let stage = stage.unwrap();
                        let path = stage.path().to_owned();
                        drop(stage);
                        path
                    })
                })
                .collect();
            ready.wait();
            let count = std::fs::read_dir(&root.0).map(|entries| entries.count());
            finish.wait();
            let paths: std::collections::BTreeSet<_> = handles
                .into_iter()
                .map(|handle| handle.join().unwrap())
                .collect();
            assert_eq!(count.unwrap(), 8);
            assert_eq!(paths.len(), 8);
        });
        assert_eq!(std::fs::read_dir(&root.0).unwrap().count(), 0);
    }
}
