//! `ms build`.

use std::path::Path;

use ms_build::Lower;
use ms_driver::project::pathops;

use super::{Engine, Failure, Target, compile_target};
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

    // The Manuscript `ms test` and `ms bench` build their executables here: the variable picks
    // the target and a `<output>.tests` file lists the source root, the project root and the
    // test or bench identities in index order.
    let target = match std::env::var("MS_BUILD_TARGET").as_deref() {
        Ok("tests") => Target::Tests,
        Ok("benches") => Target::Benches,
        _ => Target::Program,
    };
    // Further sources of one test run, one per line.
    let extra: Vec<String> = std::env::var("MS_BUILD_EXTRA")
        .map(|list| list.lines().map(str::to_string).collect())
        .unwrap_or_default();
    let mut compiled = match compile_target(syms, backend, &request.filename, &extra, target) {
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
    if let Err(message) = backend.link(
        &mut compiled,
        Path::new(&output),
        request.build_type,
        &request.link,
    ) {
        return Ok(fail(io, &compiled.source_root, "build", &message));
    }
    if target != Target::Program {
        let mut listing = format!("{}\n{}\n", compiled.source_root, compiled.project_root);
        for name in &compiled.tests {
            listing.push_str(name);
            listing.push('\n');
        }
        if let Err(error) = std::fs::write(format!("{output}.tests"), listing) {
            let message = format!("cannot write {output}.tests: {error}");
            return Ok(fail(io, &compiled.source_root, "build", &message));
        }
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

/// Inventory the build inputs that publication must not overwrite.
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
            let canonical = pathops::identity(source);
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
        || pathops::identity(artifact).as_deref() != Some(resolved)
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
        return pathops::identity(path);
    }
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    Some(pathops::identity(parent)?.join(path.file_name()?))
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
            (pathops::identity(Path::new(a_path)), pathops::identity(Path::new(b_path))),
            (Some(x), Some(y)) if x == y
        )
    }
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
}
