//! `ms build`.

use std::path::Path;

use ms_build::Lower;
use ms_driver::project::pathops;

use super::{Engine, Failure, compile, write_metadata};
use crate::backend::{BackendResult, BuildRequest, Io};
use crate::diagnostic::{CommandDiagnostic, Position};
use crate::json::Json;
use crate::profile::native_document;
use crate::util::emit_json;

/// The two artifacts `ms build` leaves: the executable and its metadata.
fn artifacts(output: &str, executable_built: bool) -> Vec<(&'static str, String, &'static str)> {
    let metadata = format!("{output}.ms-build.json");
    [
        ("executable", output.to_string()),
        ("build_metadata", metadata),
    ]
    .into_iter()
    .map(|(kind, path)| {
        let state = if executable_built {
            "verified"
        } else {
            match std::fs::metadata(&path) {
                Ok(info) if info.is_file() => "preserved",
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => "missing",
                _ => "unavailable",
            }
        };
        (kind, path, state)
    })
    .collect()
}

pub(super) fn build<L: Lower>(
    syms: ms_syntax::Names,
    backend: &Engine<L>,
    request: &BuildRequest,
    io: &mut Io,
) -> BackendResult {
    let display = if request.output.is_empty() {
        "program"
    } else {
        &request.output
    };
    let structured = request.json;
    let (output, path_error) = match pathops::abs(display) {
        Ok(absolute) => (absolute, None),
        Err(error) => (display.to_string(), Some(error.to_string())),
    };
    let document = |source_root: &str,
                    completed: bool,
                    status: i32,
                    reason: Option<&str>,
                    diagnostics: &[CommandDiagnostic]| {
        native_document(
            "build",
            source_root,
            request.build_type,
            &output,
            completed,
            status,
            reason,
            &artifacts(&output, completed),
            b"",
            diagnostics,
        )
    };
    let fail = |io: &mut Io, source_root: &str, phase: &str, message: &str| -> i32 {
        let _ = writeln!(io.stderr, "{message}");
        if !structured {
            return 1;
        }
        let diagnostic = CommandDiagnostic {
            severity: String::new(),
            code: "MSN001".into(),
            phase: phase.into(),
            message: message.into(),
            position: Position::new(&request.filename, 1, 1),
            end: None,
            fix: None,
        };
        let reason = format!("{phase}_error");
        emit_json(
            io,
            &document(source_root, false, 1, Some(&reason), &[diagnostic]),
            1,
        )
    };

    // An unchanged build is restored without loading or checking the source graph.
    let cache = BuildCache::open(backend, request, &output);
    if path_error.is_none()
        && let Some(cache) = &cache
        && cache.mode == ms_build::cache::Mode::On
        && let Some(entry) = cache.lookup()
        && artifact_source_collision(&output, &request.filename, entry.inputs()).is_none()
        && entry.restore_to(&output).is_ok()
        && write_metadata(Path::new(&output), request.build_type, entry.backend).is_ok()
    {
        if structured {
            return Ok(emit_json(
                io,
                &document(&entry.source_root, true, 0, None, &[]),
                0,
            ));
        }
        let _ = writeln!(io.stdout, "Built {display}");
        return Ok(0);
    }

    let mut compiled = match compile(syms, backend, &request.filename, false) {
        Ok(compiled) => compiled,
        Err(failure) => return Ok(report_failure(&failure, structured, &document, io)),
    };
    if let Some(error) = path_error {
        return Ok(fail(io, &compiled.source_root, "build", &error));
    }
    let mut sources = match build_inputs(&compiled) {
        Ok(sources) => sources,
        Err(message) => return Ok(fail(io, &compiled.source_root, "build", &message)),
    };
    // The native inputs the linker reads are preserved like sources: publication must not
    // replace a `--link` file, the selected runtime archive or the runtime helper IR.
    sources.extend(request.link.iter().map(std::path::PathBuf::from));
    let options = backend.build_options();
    let runtime = match backend.runtime_path() {
        Ok(runtime) => runtime,
        Err(message) => return Ok(fail(io, &compiled.source_root, "build", &message)),
    };
    sources.extend(ms_build::native_inputs(&options, &runtime));
    if std::fs::metadata(&output).is_ok_and(|m| m.is_dir()) {
        let _ = writeln!(
            io.stderr,
            "-o {display} is a directory; pass a file path (e.g. -o {})",
            pathops::join(&[display, "program"])
        );
        return Ok(2);
    }
    if let Some(protected) = protected_output(&output, &request.filename, &compiled.project_root) {
        let _ = writeln!(
            io.stderr,
            "-o {display} would overwrite {protected}; choose a different executable path"
        );
        return Ok(2);
    }
    if let Some(collision) = artifact_source_collision(
        &output,
        &request.filename,
        sources.iter().map(std::path::PathBuf::as_path),
    ) {
        let artifact = collision.artifact;
        let source = collision.source.display();
        let message = if collision.ambiguous {
            format!(
                "cannot distinguish {artifact} from source link {source}; use exact existing filename spellings or choose a different executable path"
            )
        } else {
            format!("{artifact} would overwrite {source}; choose a different executable path")
        };
        return Ok(fail(io, &compiled.source_root, "build", &message));
    }
    if let Some(parent) = Path::new(&output).parent()
        && let Err(error) = std::fs::create_dir_all(parent)
    {
        let message = format!("cannot create {}: {error}", parent.display());
        return Ok(fail(io, &compiled.source_root, "build", &message));
    }
    // The cache stores this build's own executable, not whatever a concurrent build has since
    // put at the shared output path.
    let pin = if cache.is_some() {
        match ArtifactPin::create(Path::new(&output)) {
            Ok(pin) => Some(pin),
            Err(error) => return Ok(fail(io, &compiled.source_root, "build", &error.to_string())),
        }
    } else {
        None
    };
    let linked = backend.link_pinned(
        &mut compiled,
        Path::new(&output),
        request.build_type,
        &request.link,
        pin.as_ref().map(ArtifactPin::path),
    );
    let recorded = match (&cache, linked) {
        (_, Err(message)) => Err(message),
        (Some(cache), Ok(selected)) => cache.record(
            &compiled,
            &sources,
            pin.as_ref().map_or(Path::new(&output), ArtifactPin::path),
            selected,
        ),
        (None, Ok(_)) => Ok(()),
    };
    drop(pin);
    if let Err(message) = recorded {
        return Ok(fail(io, &compiled.source_root, "build", &message));
    }
    if structured {
        return Ok(emit_json(
            io,
            &document(&compiled.source_root, true, 0, None, &[]),
            0,
        ));
    }
    let _ = writeln!(io.stdout, "Built {display}");
    Ok(0)
}

/// Inventory inputs before publication, and retain the same list for the next cache hit.
fn build_inputs(compiled: &super::Compiled) -> Result<Vec<std::path::PathBuf>, String> {
    let mut sources = compiled.sources.clone();
    // A single-file build reads the enclosing manifest even though `project_root` is empty.
    let manifest = Path::new(&compiled.source_root).join("ms.toml");
    if manifest.is_file() {
        let project = ms_driver::project::read_project(&manifest.to_string_lossy())
            .map_err(|error| error.to_string())?;
        for directory in project.embed.values() {
            sources.extend(
                ms_driver::project::embed::inputs(directory).map_err(|error| error.to_string())?,
            );
        }
        sources.push(manifest);
    }
    if !compiled.project_root.is_empty() {
        sources.push(Path::new(&compiled.project_root).join("ms.toml"));
    }
    Ok(sources)
}

struct ArtifactCollision {
    artifact: &'static str,
    source: std::path::PathBuf,
    ambiguous: bool,
}

fn artifact_source_collision<'a>(
    output: &str,
    input: &'a str,
    sources: impl Iterator<Item = &'a Path>,
) -> Option<ArtifactCollision> {
    let executable = publication_entry(Path::new(output));
    let metadata = publication_entry(Path::new(&format!("{output}.ms-build.json")));
    if executable.is_none() && metadata.is_none() {
        return None;
    }
    std::iter::once(Path::new(input))
        .chain(sources)
        .find_map(|source| {
            let canonical = std::fs::canonicalize(source).ok();
            // A regular source's canonical path is already its publication entry. Only the
            // requested final symlink needs its own entry checked as well as its target.
            let entry = std::fs::symlink_metadata(source)
                .is_ok_and(|metadata| metadata.file_type().is_symlink())
                .then(|| publication_entry(source))
                .flatten();
            [
                ("executable", executable.as_ref()),
                ("build metadata", metadata.as_ref()),
            ]
            .into_iter()
            .find_map(|(artifact, target)| {
                let target = target?;
                let exact = entry.as_ref() == Some(target) || canonical.as_ref() == Some(target);
                let ambiguous = !exact
                    && entry.as_deref().zip(canonical.as_deref()).is_some_and(
                        |(entry, resolved)| ambiguous_symlink_alias(entry, target, resolved),
                    );
                (exact || ambiguous).then(|| ArtifactCollision {
                    artifact,
                    source: source.to_path_buf(),
                    ambiguous,
                })
            })
        })
}

// Following the last link loses its identity. If two such paths have the same parent and
// target, require evidence of two distinct entries rather than guessing filesystem case rules.
fn ambiguous_symlink_alias(source: &Path, artifact: &Path, resolved: &Path) -> bool {
    if source.parent() != artifact.parent()
        || !std::fs::symlink_metadata(artifact).is_ok_and(|m| m.file_type().is_symlink())
        || std::fs::canonicalize(artifact).ok().as_deref() != Some(resolved)
    {
        return false;
    }
    let (Some(parent), Some(source_name), Some(artifact_name)) =
        (source.parent(), source.file_name(), artifact.file_name())
    else {
        return true;
    };
    let distinct = std::fs::read_dir(parent).and_then(|entries| {
        distinct_names(
            entries.map(|entry| entry.map(|entry| entry.file_name())),
            source_name,
            artifact_name,
        )
    });
    !distinct.unwrap_or(false)
}

fn distinct_names(
    names: impl IntoIterator<Item = std::io::Result<std::ffi::OsString>>,
    first: &std::ffi::OsStr,
    second: &std::ffi::OsStr,
) -> std::io::Result<bool> {
    if first == second {
        return Ok(false);
    }
    let (mut found_first, mut found_second) = (false, false);
    for name in names {
        let name = name?;
        found_first |= name == first;
        found_second |= name == second;
        if found_first && found_second {
            return Ok(true);
        }
    }
    Ok(false)
}

// Publication replaces the final directory entry, so do not follow its last symlink or compare
// inode identities: a distinct metadata hard link/symlink to source is safe to replace (#2271).
fn publication_entry(path: &Path) -> Option<std::path::PathBuf> {
    if std::fs::symlink_metadata(path).is_ok_and(|m| !m.file_type().is_symlink()) {
        return std::fs::canonicalize(path).ok();
    }
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    Some(std::fs::canonicalize(parent).ok()?.join(path.file_name()?))
}

/// Builds the `--json` document from `(source_root, completed, status, reason, diagnostics)`.
type DocumentFn<'a> = dyn Fn(&str, bool, i32, Option<&str>, &[CommandDiagnostic]) -> Json + 'a;

/// Report compile diagnostics as text or as the command's JSON document.
fn report_failure(failure: &Failure, structured: bool, document: &DocumentFn, io: &mut Io) -> i32 {
    if !structured {
        return failure.report(io);
    }
    let diagnostics = failure.command_diagnostics();
    emit_json(
        io,
        &document(
            &failure.source_root,
            false,
            1,
            Some("compile_error"),
            &diagnostics,
        ),
        1,
    )
}

/// The source or manifest file an `-o` path would replace, or `None` when the
/// output is safe to write.
pub(super) fn protected_output(output: &str, input: &str, project_root: &str) -> Option<String> {
    let mut candidates = vec![input.to_string()];
    if !project_root.is_empty() {
        candidates.push(pathops::join(&[project_root, "ms.toml"]));
    }
    if let Ok(info) = std::fs::metadata(output) {
        for candidate in &candidates {
            if let Ok(other) = std::fs::metadata(candidate)
                && same_file(&info, &other, output, candidate)
            {
                return Some(pathops::base(candidate));
            }
        }
    }
    let base = pathops::base(output);
    (base.ends_with(".ms") || base == "ms.toml").then_some(base)
}

/// Whether two paths with the given metadata name one file.
fn same_file(a: &std::fs::Metadata, b: &std::fs::Metadata, a_path: &str, b_path: &str) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let _ = (a_path, b_path);
        (a.dev(), a.ino()) == (b.dev(), b.ino())
    }
    #[cfg(not(unix))]
    {
        let _ = (a, b);
        matches!(
            (std::fs::canonicalize(a_path), std::fs::canonicalize(b_path)),
            (Ok(x), Ok(y)) if x == y
        )
    }
}

/// The `ms build` cache of one request: see [`ms_build::cache`].
struct BuildCache {
    mode: ms_build::cache::Mode,
    directory: std::path::PathBuf,
    key: String,
}

impl BuildCache {
    /// `None` when caching is off or an input of the key cannot be read.
    fn open<L: Lower>(backend: &Engine<L>, request: &BuildRequest, output: &str) -> Option<Self> {
        let mode = ms_build::cache::mode();
        if mode == ms_build::cache::Mode::Off {
            return None;
        }
        let filename = pathops::abs(&request.filename).ok()?;
        let directory = Path::new(&filename)
            .parent()?
            .join(".ms-cache")
            .join("build");
        let mut inputs = vec![std::env::current_exe().ok()?];
        // The lexical entry name can keep pointing at a different file after a symlink changes.
        // Its selected identity must be part of the key, not only the old graph's source stamps.
        inputs.push(std::fs::canonicalize(&filename).ok()?);
        if pathops::base(&filename) == "ms.toml" {
            let project = ms_driver::project::read_project(&filename).ok()?;
            inputs.push(std::path::PathBuf::from(project.entry));
        }
        // A newly created nearer manifest can change resolution without changing any recorded
        // source. Include the current selection in the key, resolving directory symlinks as the
        // loader does, so even a previously absent manifest invalidates a cached program.
        let source_dir = pathops::eval_symlinks(&pathops::dir(&filename)).ok()?;
        let manifest = ms_driver::load::enclosing_manifest(&source_dir);
        inputs.extend(manifest.clone().map(std::path::PathBuf::from));
        // An alias or the source directory that is a symlink can be retargeted without touching
        // any recorded source or the manifest, so the key names where each one resolves now.
        // The directories themselves are not stamped: building into one changes its mtime.
        let mut resolved = Vec::new();
        if let Some(manifest) = manifest
            && let Ok(project) = ms_driver::project::read_project(&manifest)
        {
            for target in project.aliases.values().chain([&project.source]) {
                resolved.push(std::fs::canonicalize(target).ok()?.display().to_string());
            }
        }
        inputs.push(backend.runtime_path().ok()?);
        let options = backend.build_options();
        inputs.extend(request.link.iter().map(std::path::PathBuf::from));
        let inputs: Vec<&Path> = inputs.iter().map(std::path::PathBuf::as_path).collect();
        let build_type = request.build_type.as_str();
        let mut parts = vec![build_type, filename.as_str(), output, crate::VERSION];
        parts.extend(request.link.iter().map(String::as_str));
        parts.extend(resolved.iter().map(String::as_str));
        parts.push(if options.static_musl { "musl" } else { "libc" });
        let key = ms_build::cache::key(&parts, &inputs, &options)?;
        Some(BuildCache {
            mode,
            directory,
            key,
        })
    }

    fn lookup(&self) -> Option<Hit> {
        ms_build::cache::lookup(&self.directory, &self.key).map(Hit)
    }

    /// Stores this producer's pinned build for the next one (or, under `MS_CACHE=verify`,
    /// compares it with the stored build).
    fn record(
        &self,
        compiled: &super::Compiled,
        sources: &[std::path::PathBuf],
        artifact: &Path,
        backend: ms_build::Backend,
    ) -> Result<(), String> {
        if self.mode == ms_build::cache::Mode::Verify {
            let Some(hit) = self.lookup() else {
                return Ok(());
            };
            if hit.0.matches(artifact) {
                return Ok(());
            }
            return Err("MS_CACHE=verify: the rebuilt executable differs from the cached one (this is a Manuscript bug)".into());
        }
        let companion = ms_clif_companion(artifact);
        ms_build::cache::store(
            &self.directory,
            &self.key,
            &compiled.source_root,
            backend,
            sources,
            artifact,
            companion.as_deref(),
        );
        Ok(())
    }
}

struct Hit(ms_build::cache::Entry);

impl std::ops::Deref for Hit {
    type Target = ms_build::cache::Entry;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl Hit {
    /// Publishes the stored executable (and macOS debug companion) at `output`.
    fn restore_to(&self, output: &str) -> Result<(), String> {
        let output = Path::new(output);
        let stage = ms_build::native::BuildStage::for_output(output).map_err(|e| e.to_string())?;
        let staged = stage.path().join("program.exe");
        let companion = ms_clif_companion(&staged);
        let published = if self.0.restore(&staged, companion.as_deref()) {
            ms_build::publish(&staged, output).map_err(|e| e.to_string())
        } else {
            Err("cannot restore the cached build".to_string())
        };
        if published.is_err() {
            let _ = std::fs::remove_file(&staged);
            if let Some(c) = companion {
                let _ = std::fs::remove_dir_all(c);
            }
        }
        published
    }
}

/// Own both pins until recording has finished, including on link or metadata failure.
struct ArtifactPin {
    _stage: ms_build::native::BuildStage,
    executable: std::path::PathBuf,
}

impl ArtifactPin {
    fn create(output: &Path) -> std::io::Result<Self> {
        let stage = ms_build::native::BuildStage::for_output(output)?;
        let executable = stage.path().join("program.exe");
        Ok(Self {
            _stage: stage,
            executable,
        })
    }

    fn path(&self) -> &Path {
        &self.executable
    }
}

impl Drop for ArtifactPin {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(self.path());
        if let Some(companion) = ms_clif_companion(self.path()) {
            let _ = std::fs::remove_dir_all(companion);
        }
    }
}

/// The macOS `.dSYM` directory beside `executable`; none elsewhere.
fn ms_clif_companion(executable: &Path) -> Option<std::path::PathBuf> {
    ms_build::debug_companion_path(executable)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distinct_alias_names_require_two_exact_directory_entries() {
        use std::ffi::{OsStr, OsString};
        let first = OsStr::new("Program.ms-build.json");
        let second = OsStr::new("program.ms-build.json");
        for (names, expected) in [
            (vec!["Program.ms-build.json"], false),
            (vec!["program.ms-build.json"], false),
            (vec!["PROGRAM.ms-build.json"], false),
            (
                vec!["Program.ms-build.json", "Program.ms-build.json"],
                false,
            ),
            (
                vec![
                    "unrelated",
                    "program.ms-build.json",
                    "Program.ms-build.json",
                ],
                true,
            ),
        ] {
            assert_eq!(
                distinct_names(
                    names.into_iter().map(|name| Ok(OsString::from(name))),
                    first,
                    second
                )
                .unwrap(),
                expected
            );
        }
        assert!(!distinct_names([Ok(first.to_owned())], first, first).unwrap());
        assert!(
            distinct_names(
                [Ok(OsString::from("É.ms")), Ok(OsString::from("é.ms"))],
                OsStr::new("É.ms"),
                OsStr::new("é.ms")
            )
            .unwrap()
        );
    }

    #[test]
    fn failed_directory_enumeration_cannot_prove_distinct_aliases() {
        use std::ffi::{OsStr, OsString};
        let names = [
            Ok(OsString::from("source.ms")),
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied)),
            Ok(OsString::from("program.ms-build.json")),
        ];
        let distinct = distinct_names(
            names,
            OsStr::new("source.ms"),
            OsStr::new("program.ms-build.json"),
        );
        assert!(distinct.is_err());
        assert!(!distinct.unwrap_or(false));
    }

    fn hit(directory: &Path, key: &str, payload: &[u8]) -> Hit {
        let source = directory.join(format!("{key}.source"));
        let executable = directory.join(format!("{key}.cached"));
        std::fs::write(&source, b"source").unwrap();
        std::fs::write(&executable, payload).unwrap();
        let companion = directory.join(format!("{key}.debug"));
        let resources = companion.join("Contents/Resources/DWARF");
        std::fs::create_dir_all(&resources).unwrap();
        std::fs::write(resources.join("cached"), payload).unwrap();
        let cache = directory.join("cache");
        ms_build::cache::store(
            &cache,
            key,
            "root",
            ms_build::Backend::Cranelift,
            &[source],
            &executable,
            Some(&companion),
        );
        Hit(ms_build::cache::lookup(&cache, key).unwrap())
    }

    fn assert_restored(output: &Path, payload: &[u8]) {
        assert_eq!(std::fs::read(output).unwrap(), payload);
        if let Some(companion) = ms_clif_companion(output) {
            assert_eq!(
                std::fs::read(
                    companion
                        .join("Contents/Resources/DWARF")
                        .join(output.file_name().unwrap())
                )
                .unwrap(),
                payload
            );
        }
    }

    #[test]
    fn cache_restore_preserves_existing_staging_links() {
        let scratch = super::super::TempDir::create("ms-cache-restore-links-").unwrap();
        let root = &scratch.0;
        let hit = hit(root, "entry", b"cached executable");
        let directory = root.join("output");
        std::fs::create_dir(&directory).unwrap();
        let victim = directory.join("victim");
        std::fs::write(&victim, b"retained contents").unwrap();
        let stale = directory.join(format!(".ms-build-{}.exe", std::process::id()));
        std::fs::hard_link(&victim, &stale).unwrap();
        let output = directory.join("program");
        for _ in 0..2 {
            hit.restore_to(output.to_str().unwrap()).unwrap();
            assert_restored(&output, b"cached executable");
            assert_eq!(std::fs::read(&victim).unwrap(), b"retained contents");
            assert_eq!(std::fs::read(&stale).unwrap(), b"retained contents");
        }
    }

    #[test]
    fn cache_restore_recreates_a_removed_output_parent() {
        let scratch = super::super::TempDir::create("ms-cache-restore-parent-").unwrap();
        let root = &scratch.0;
        let hit = hit(root, "entry", b"cached executable");
        let ancestor = root.join("output");
        let output = ancestor.join("nested/program");
        hit.restore_to(output.to_str().unwrap()).unwrap();
        assert_restored(&output, b"cached executable");
        std::fs::remove_dir_all(&ancestor).unwrap();
        hit.restore_to(output.to_str().unwrap()).unwrap();
        assert_restored(&output, b"cached executable");
    }

    #[test]
    fn cache_restore_output_can_use_a_staging_directory_name() {
        let scratch = super::super::TempDir::create("ms-cache-restore-name-").unwrap();
        let root = &scratch.0;
        let hit = hit(root, "entry", b"cached executable");
        let directory = root.join("output");
        for uppercase in [false, true] {
            let probe = ms_build::native::BuildStage::create(&directory).unwrap();
            let name = probe.path().file_name().unwrap().to_str().unwrap();
            let (prefix, counter) = name.rsplit_once('-').unwrap();
            let mut name = format!("{prefix}-{}", counter.parse::<usize>().unwrap() + 1);
            if uppercase {
                name.make_ascii_uppercase();
            }
            let output = directory.join(name);
            drop(probe);
            hit.restore_to(output.to_str().unwrap()).unwrap();
            assert_restored(&output, b"cached executable");
        }
    }

    #[test]
    fn failed_cache_restore_publication_cleans_only_its_owned_files() {
        let scratch = super::super::TempDir::create("ms-cache-restore-failure-").unwrap();
        let root = &scratch.0;
        let hit = hit(root, "entry", b"cached executable");
        let directory = root.join("output");
        let output = directory.join("blocked");
        std::fs::create_dir_all(&output).unwrap();
        std::fs::write(output.join("retained"), b"original directory").unwrap();
        if let Some(companion) = ms_clif_companion(&output) {
            std::fs::create_dir_all(&companion).unwrap();
            std::fs::write(companion.join("retained"), b"original companion").unwrap();
        }
        let entries = || {
            std::fs::read_dir(&directory)
                .unwrap()
                .map(|entry| entry.unwrap().file_name())
                .collect::<std::collections::BTreeSet<_>>()
        };
        let previous = entries();
        assert!(hit.restore_to(output.to_str().unwrap()).is_err());
        assert_eq!(
            std::fs::read(output.join("retained")).unwrap(),
            b"original directory"
        );
        if let Some(companion) = ms_clif_companion(&output) {
            assert_eq!(
                std::fs::read(companion.join("retained")).unwrap(),
                b"original companion"
            );
        }
        assert_eq!(
            entries(),
            previous,
            "failed publication must leave no staging residue"
        );
        let recovered = directory.join("recovered");
        hit.restore_to(recovered.to_str().unwrap()).unwrap();
        assert_restored(&recovered, b"cached executable");
    }

    #[test]
    fn concurrent_cache_restores_keep_distinct_outputs_and_companions() {
        let scratch = super::super::TempDir::create("ms-cache-restore-concurrent-").unwrap();
        let root = &scratch.0;
        let first = hit(root, "first", b"first executable");
        let second = hit(root, "second", b"second executable");
        let directory = root.join("output");
        let ready = std::sync::Barrier::new(8);
        std::thread::scope(|scope| {
            let handles: Vec<_> = (0..8)
                .map(|index| {
                    let hit = if index % 2 == 0 { &first } else { &second };
                    let payload = if index % 2 == 0 {
                        b"first executable".as_slice()
                    } else {
                        b"second executable".as_slice()
                    };
                    let output = directory.join(format!("program-{index}"));
                    let ready = &ready;
                    scope.spawn(move || {
                        ready.wait();
                        for _ in 0..8 {
                            hit.restore_to(output.to_str().unwrap()).unwrap();
                            assert_restored(&output, payload);
                        }
                    })
                })
                .collect();
            for handle in handles {
                handle.join().unwrap();
            }
        });
        let mut expected = std::collections::BTreeSet::new();
        for index in 0..8 {
            let output = directory.join(format!("program-{index}"));
            expected.insert(output.file_name().unwrap().to_owned());
            if let Some(companion) = ms_clif_companion(&output) {
                expected.insert(companion.file_name().unwrap().to_owned());
            }
        }
        let actual = std::fs::read_dir(directory)
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect::<std::collections::BTreeSet<_>>();
        assert_eq!(actual, expected);
    }
}

#[cfg(test)]
mod cache_provenance;
