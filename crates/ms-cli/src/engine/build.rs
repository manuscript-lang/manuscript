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
        && entry.restore_to(&output).is_ok()
        && write_metadata(Path::new(&output), request.build_type).is_ok()
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

    let mut compiled = match compile(backend, &request.filename, false) {
        Ok(compiled) => compiled,
        Err(failure) => return Ok(report_failure(&failure, structured, &document, io)),
    };
    if let Some(error) = path_error {
        return Ok(fail(io, &compiled.source_root, "build", &error));
    }
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
    if let Some(parent) = Path::new(&output).parent()
        && let Err(error) = std::fs::create_dir_all(parent)
    {
        let message = format!("cannot create {}: {error}", parent.display());
        return Ok(fail(io, &compiled.source_root, "build", &message));
    }
    if let Err(message) = backend.link(
        &mut compiled,
        Path::new(&output),
        request.build_type,
        &request.link,
    ) {
        return Ok(fail(io, &compiled.source_root, "build", &message));
    }
    if let Some(cache) = &cache
        && let Err(message) = cache.record(&compiled, &output)
    {
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
        inputs
            .extend(ms_driver::load::enclosing_manifest(&source_dir).map(std::path::PathBuf::from));
        inputs.extend(backend.runtime.clone());
        inputs.extend(ms_build::runtime_override().ok()?);
        inputs.extend(request.link.iter().map(std::path::PathBuf::from));
        let inputs: Vec<&Path> = inputs.iter().map(std::path::PathBuf::as_path).collect();
        let build_type = request.build_type.as_str();
        let mut parts = vec![build_type, filename.as_str(), output, crate::VERSION];
        parts.extend(request.link.iter().map(String::as_str));
        parts.push(if ms_build::static_libc() {
            "musl"
        } else {
            "libc"
        });
        let key = ms_build::cache::key(&parts, &inputs)?;
        Some(BuildCache {
            mode,
            directory,
            key,
        })
    }

    fn lookup(&self) -> Option<Hit> {
        ms_build::cache::lookup(&self.directory, &self.key).map(Hit)
    }

    /// Stores the finished build at `output` for the next one (or, under `MS_CACHE=verify`,
    /// compares it with the stored build).
    fn record(&self, compiled: &super::Compiled, output: &str) -> Result<(), String> {
        let output = Path::new(output);
        if self.mode == ms_build::cache::Mode::Verify {
            let Some(hit) = self.lookup() else {
                return Ok(());
            };
            if hit.0.matches(output) {
                return Ok(());
            }
            return Err("MS_CACHE=verify: the rebuilt executable differs from the cached one (this is a Manuscript bug)".into());
        }
        let mut sources = compiled.sources.clone();
        // A single-file build still reads the nearest enclosing manifest (import root and
        // aliases), which lives in the source root even though `project_root` is empty.
        let manifest = Path::new(&compiled.source_root).join("ms.toml");
        if manifest.is_file() {
            sources.push(manifest);
        }
        let companion = ms_clif_companion(output);
        ms_build::cache::store(
            &self.directory,
            &self.key,
            &compiled.source_root,
            &sources,
            output,
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
        let directory = output
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new("."));
        std::fs::create_dir_all(directory).map_err(|e| e.to_string())?;
        let staged = directory.join(format!(".ms-build-{}.exe", std::process::id()));
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

/// The macOS `.dSYM` directory beside `executable`; none elsewhere.
fn ms_clif_companion(executable: &Path) -> Option<std::path::PathBuf> {
    ms_build::debug_companion_path(executable)
}
