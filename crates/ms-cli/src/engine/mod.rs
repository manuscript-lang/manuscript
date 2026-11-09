//! The Rust engine behind `ms build`, `ms run`, `ms test` (and, through them,
//! `ms profile`): source to Cranelift-compiled native executable.
//!
//! ```text
//! ms_driver::load_file -> check_graph -> Lower -> optimize -> ms-clif -> link with ms-native
//! ```
//!
//! [`Engine`] is generic over the [`Lower`] stage so tests can inject a lowering.

mod build;
mod options;
pub use options::from_env as build_options_from_env;
mod run;
mod runtime;
mod search;
pub mod testing;
mod tooling;
mod watch;

pub use search::search_symbol;
pub use tooling::{
    analysis, diagram, drop_redundant_labels, format_source, inspect_command as inspect, review,
};

use std::path::{Path, PathBuf};

use ms_build::Lower;
use ms_driver::{
    CheckRequest, Diagnostic, Graph, LoadOptions, Phase, Pos, check_graph, load_files,
};

use crate::backend::{
    BackendError, BackendResult, BuildRequest, BuildType, Io, OutputRequest, RunRequest,
    TestRequest,
};
use crate::diagnostic::{CommandDiagnostic, Position};
use crate::json::Json;
use crate::util::plural;

/// The `ms` engine for native builds. `L` turns a checked program into MIR.
pub struct Engine<L: Lower> {
    pub lowering: L,
    /// The native static library to link; `MS_RT_LIB`, then the archive
    /// embedded in `ms` (see [`runtime`]), when unset.
    pub runtime: Option<PathBuf>,
    /// Codegen and link settings: the `MS_*` variables, read when the engine was created.
    build: ms_build::BuildOptions,
    /// `--static` of the current command: link static musl.
    static_libc: std::cell::Cell<bool>,
}

impl<L: Lower> Engine<L> {
    pub fn new(lowering: L) -> Engine<L> {
        Engine {
            lowering,
            runtime: None,
            build: options::from_env(),
            static_libc: std::cell::Cell::new(false),
        }
    }

    /// Select static musl (`--static`) or glibc for the commands that follow.
    pub fn set_static_libc(&self, on: bool) {
        self.static_libc.set(on);
    }

    /// The build settings of the current command.
    pub(crate) fn build_options(&self) -> ms_build::BuildOptions {
        ms_build::BuildOptions {
            static_musl: self.static_libc.get(),
            ..self.build.clone()
        }
    }

    /// Link against `runtime` instead of searching for it.
    pub fn with_runtime(mut self, runtime: impl Into<PathBuf>) -> Engine<L> {
        self.runtime = Some(runtime.into());
        self
    }

    /// The archive selected for linking and for build-input publication protection.
    pub(crate) fn runtime_path(&self) -> Result<PathBuf, String> {
        if let Some(runtime) = &self.runtime {
            return Ok(runtime.clone());
        }
        let build = self.build_options();
        if let Some(runtime) = ms_build::runtime_override(&build)? {
            return Ok(runtime);
        }
        runtime::embedded(build.static_musl)
    }

    /// Compile the lowered module into the executable `output`.
    pub(crate) fn link(
        &self,
        compiled: &mut Compiled,
        output: &Path,
        kind: BuildType,
        link: &[String],
    ) -> Result<ms_build::Backend, String> {
        self.link_pinned(compiled, output, kind, link, None)
    }

    /// `link` that also leaves this build's own executable at `pin`.
    pub(crate) fn link_pinned(
        &self,
        compiled: &mut Compiled,
        output: &Path,
        kind: BuildType,
        link: &[String],
        pin: Option<&Path>,
    ) -> Result<ms_build::Backend, String> {
        let build = self.build_options();
        let runtime = self.runtime_path()?;
        let extra: Vec<PathBuf> = link.iter().map(PathBuf::from).collect();
        let backend = ms_build::build_executable_pinned(
            &mut compiled.module,
            output,
            profile(kind),
            &runtime,
            &extra,
            &build,
            pin,
        )?;
        write_metadata(output, kind, backend)?;
        Ok(backend)
    }
}

impl<L: Lower> Engine<L> {
    pub fn build(
        &self,
        syms: ms_syntax::Names,
        request: &BuildRequest,
        io: &mut Io,
    ) -> BackendResult {
        build::build(syms, self, request, io)
    }

    pub fn run(&self, syms: ms_syntax::Names, request: &RunRequest, io: &mut Io) -> BackendResult {
        if request.watch {
            return watch::run(syms, self, request, io);
        }
        run::run(syms, self, request, io)
    }

    pub fn test(
        &self,
        syms: ms_syntax::Names,
        request: &TestRequest,
        io: &mut Io,
    ) -> BackendResult {
        if request.watch {
            return watch::test(syms, self, request, io);
        }
        testing::test(syms, self, request, io)
    }

    /// `ms bench`: `request.arguments` are the `ms test` selection options plus `--time=`,
    /// `--samples=` and `--iterations=`.
    pub fn bench(
        &self,
        syms: ms_syntax::Names,
        request: &TestRequest,
        io: &mut Io,
    ) -> BackendResult {
        testing::bench(syms, self, request, io)
    }

    pub fn emit(
        &self,
        syms: ms_syntax::Names,
        request: &OutputRequest,
        io: &mut Io,
    ) -> BackendResult {
        let compiled = match compile(syms, self, &request.filename, false) {
            Ok(compiled) => compiled,
            Err(failure) if request.json => {
                let document =
                    crate::diagnostic::diagnostics_document(&failure.command_diagnostics());
                return Ok(crate::util::emit_json(io, &document, 1));
            }
            Err(failure) => return Ok(failure.report(io)),
        };
        let mut module = compiled.module;
        // `MS_EMIT_OPT=1` prints the code after the optimizer, the form that gets compiled.
        if std::env::var_os("MS_EMIT_OPT").is_some_and(|v| v == "1") {
            ms_mir::opt::optimize(&mut module, ms_mir::opt::Level::Speed, false);
        }
        let text = ms_mir::print::print_module(&module);
        Ok(crate::util::write_output(
            io,
            &request.output,
            text.as_bytes(),
        ))
    }
}

/// Serve the language server until the client disconnects. The server reads
/// the process stdin itself: the supervisor's reader runs on its own thread
/// and needs a `'static` stream.
pub fn lsp(syms: ms_syntax::Names, io: &mut Io) -> BackendResult {
    let served = if std::env::var_os(LSP_WORKER).is_some() {
        ms_lsp::serve(syms, std::io::stdin(), &mut *io.stdout)
    } else {
        ms_lsp::supervise(std::io::stdin(), &mut *io.stdout, || {
            let exe = std::env::current_exe().unwrap_or_else(|_| "ms".into());
            let mut command = std::process::Command::new(exe);
            command.arg("lsp").env(LSP_WORKER, "1");
            command
        })
    };
    match served {
        Ok(()) => Ok(0),
        Err(message) => Err(BackendError(format!("ms lsp: {message}"))),
    }
}

/// Set in the environment of the server process the supervisor restarts.
const LSP_WORKER: &str = "MS_LSP_WORKER";

/// A command's source failed to load, check or lower.
pub(crate) struct Failure {
    pub source_root: String,
    pub diagnostics: Vec<Diagnostic>,
}

impl Failure {
    /// The terminal report: `file:line:col: phase: message` per diagnostic, then a count.
    pub fn report(&self, io: &mut Io) -> i32 {
        let mut sources = crate::snippet::Sources::default();
        for issue in self.in_source_order() {
            let mut issue = issue.clone();
            if !self.source_root.is_empty()
                && !issue.file.starts_with('/')
                && !std::path::Path::new(&*issue.file).is_absolute()
            {
                issue.file = format!("{}/{}", self.source_root, issue.file).into();
            }
            let end = issue.end.map(|e| (e.line as usize, e.column as usize));
            let excerpt = sources.excerpt(
                &issue.file,
                issue.pos.line as usize,
                issue.pos.column as usize,
                end,
            );
            let _ = writeln!(io.stderr, "{issue}{excerpt}");
        }
        let count = self.diagnostics.len();
        let _ = writeln!(
            io.stderr,
            "{count} {}; fix them and re-run (ms check <file> --json gives the same diagnostics as structured data)",
            plural(count, "error", "errors")
        );
        1
    }

    pub fn command_diagnostics(&self) -> Vec<CommandDiagnostic> {
        self.in_source_order()
            .into_iter()
            .map(command_diagnostic)
            .collect()
    }

    /// Diagnostics by file, line and column; the sort is stable, so ties keep
    /// the order the phases produced them in.
    fn in_source_order(&self) -> Vec<&Diagnostic> {
        let mut ordered: Vec<&Diagnostic> = self.diagnostics.iter().collect();
        ordered.sort_by(|a, b| {
            (&a.file, a.pos.line, a.pos.column).cmp(&(&b.file, b.pos.line, b.pos.column))
        });
        ordered
    }
}

/// The JSON shape of one source diagnostic.
pub(crate) fn command_diagnostic(issue: &Diagnostic) -> CommandDiagnostic {
    placed_command_diagnostic(issue, &|position| position)
}

/// Place every source coordinate, including machine-applicable edit boundaries.
pub(crate) fn placed_command_diagnostic(
    issue: &Diagnostic,
    place: &dyn Fn(Position) -> Position,
) -> CommandDiagnostic {
    let position = |pos: Pos| {
        place(Position {
            file: issue.file.to_string(),
            line: pos.line as usize,
            column: pos.column as usize,
            offset: pos.offset as usize,
        })
    };
    CommandDiagnostic {
        severity: String::new(),
        code: issue.code().to_string(),
        phase: issue.phase.as_str().to_string(),
        message: issue.message.clone(),
        position: position(issue.pos),
        end: issue.end.map(position),
        fix: issue.fix.as_ref().map(|fix| fix_json(&position, fix)),
    }
}

/// The JSON `fix` object of an edit, placed with `position`.
pub(crate) fn fix_json(position: &dyn Fn(Pos) -> Position, fix: &ms_driver::DiagnosticFix) -> Json {
    Json::object()
        .with("position", position(fix.pos).to_json())
        .with("end", position(fix.end).to_json())
        .with("replacement", Json::str(&fix.replacement))
}

/// A checked and lowered program.
pub(crate) struct Compiled {
    pub module: ms_build::Module,
    /// Full `module::name` identities in index order (test executables only).
    pub tests: Vec<String>,
    pub source_root: String,
    pub project_root: String,
    /// Every source file of the program, as paths (for the build cache).
    pub sources: Vec<std::path::PathBuf>,
}

/// What `compile` builds.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum Target {
    /// An executable program.
    Program,
    /// A test executable.
    Tests,
    /// A bench executable.
    Benches,
}

/// Load, check and lower `filename` for an executable (`tests == false`) or a
/// test executable.
pub(crate) fn compile<L: Lower>(
    syms: ms_syntax::Names,
    backend: &Engine<L>,
    filename: &str,
    tests: bool,
) -> Result<Compiled, Failure> {
    compile_target(
        syms,
        backend,
        filename,
        &[],
        if tests {
            Target::Tests
        } else {
            Target::Program
        },
    )
}

/// Load, check and lower `filename` for `target`.
pub(crate) fn compile_target<L: Lower>(
    syms: ms_syntax::Names,
    backend: &Engine<L>,
    filename: &str,
    extra: &[String],
    target: Target,
) -> Result<Compiled, Failure> {
    let tests = target != Target::Program;
    let graph = load_files(syms, filename, extra, LoadOptions { tests });
    let library = graph.library;
    let project = !graph.project_root.is_empty();
    if project && library && !tests {
        return Err(library_failure(&graph));
    }
    let entry_required = !tests && (!project || !library);
    let entry = graph.entry.clone();
    let checked = check_graph(
        syms,
        graph,
        CheckRequest {
            entry: entry_required,
        },
    );
    let failure = |diagnostics: Vec<Diagnostic>, source_root: &str| Failure {
        source_root: source_root.to_string(),
        diagnostics,
    };
    if !checked.success() {
        return Err(failure(checked.diagnostics, &checked.source_root));
    }
    let Some(program) = &checked.program else {
        return Err(failure(checked.diagnostics, &checked.source_root));
    };
    let lowered = if target == Target::Benches {
        backend.lowering.lower_benches(program, &entry)
    } else if tests {
        backend.lowering.lower_tests(program, &entry)
    } else {
        backend
            .lowering
            .lower(program, &entry)
            .map(|module| (module, Vec::new()))
    };
    match lowered {
        Ok((module, names)) => Ok(Compiled {
            module,
            tests: names,
            source_root: checked.source_root.clone(),
            project_root: checked.project_root.clone(),
            // The symbolic links an import passed through are inputs too: retargeting one
            // changes what the same source files mean while they keep their stamps.
            sources: program
                .modules
                .iter()
                .map(|m| Path::new(&checked.source_root).join(syms.str(m.file)))
                .filter(|p| p.is_file())
                .chain(
                    checked
                        .inputs
                        .iter()
                        .map(std::path::PathBuf::from)
                        .filter(|p| p.symlink_metadata().is_ok_and(|m| m.is_symlink())),
                )
                .collect(),
        }),
        Err(message) => {
            let file = if entry.is_empty() { filename } else { &entry };
            Err(failure(
                vec![Diagnostic {
                    opener_line: 0,
                    file: file.into(),
                    pos: Pos::new(0, 1, 1),
                    phase: Phase::Lowering,
                    message,
                    end: None,
                    fix: None,
                }],
                &checked.source_root,
            ))
        }
    }
}

fn library_failure(graph: &Graph) -> Failure {
    let (file, pos) = graph
        .manifest_position
        .clone()
        .unwrap_or_else(|| (String::new(), Pos::new(0, 1, 1)));
    Failure {
        source_root: graph.source_root.clone(),
        diagnostics: vec![Diagnostic {
            opener_line: 0,
            file: file.as_str().into(),
            pos,
            phase: Phase::Resolution,
            message: "library project has no executable entry; add entry = \"src/main.ms\" under [project] and export fn main() Int from that file, or use check, lint, or test for the library".to_string(),
            end: None,
            fix: None,
        }],
    }
}

/// Map the CLI's build levels onto the code generator's.
pub(crate) fn profile(kind: BuildType) -> ms_build::Profile {
    match kind {
        BuildType::Debug => ms_build::Profile::Debug,
        BuildType::Release => ms_build::Profile::Release,
        BuildType::MinSizeRel => ms_build::Profile::MinSizeRel,
    }
}

/// `<executable>.ms-build.json`: what built the executable.
fn write_metadata(
    output: &Path,
    kind: BuildType,
    backend: ms_build::Backend,
) -> Result<(), String> {
    static STAGED: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
    write_metadata_with(output, kind, backend, &STAGED)
}

fn write_metadata_with(
    output: &Path,
    kind: BuildType,
    backend: ms_build::Backend,
    next: &std::sync::atomic::AtomicUsize,
) -> Result<(), String> {
    let mut name = output.as_os_str().to_owned();
    name.push(".ms-build.json");
    let document = format!(
        "{{\n  \"format\": 1,\n  \"version\": {},\n  \"backend\": \"{}\",\n  \"build_type\": \"{}\"\n}}\n",
        crate::quote(crate::VERSION),
        backend.as_str(),
        kind.as_str()
    );
    let path = PathBuf::from(name);
    let failed = |error| {
        format!(
            "cannot write build metadata {}: {error}; choose an output path whose .ms-build.json file can be written",
            path.display()
        )
    };
    // Replace the directory entry, as executable publication does. Writing through an existing
    // metadata hard link or symlink could otherwise truncate a source file (also on cache hits).
    let (staged, mut file) = loop {
        let staged = path.with_file_name(format!(
            ".ms-metadata-{}-{}.json",
            std::process::id(),
            next.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        ));
        match std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&staged)
        {
            Ok(file) => break (staged, file),
            Err(error) if occupied_staging_file(&staged, &error) => continue,
            Err(error) => return Err(failed(error)),
        }
    };
    let written = (|| {
        std::io::Write::write_all(&mut file, document.as_bytes())?;
        drop(file);
        std::fs::rename(&staged, &path)
    })();
    written.map_err(|error| {
        let _ = std::fs::remove_file(&staged);
        failed(error)
    })
}

/// Windows also reports access denied when exclusive file creation meets an existing directory.
/// Inspect the entry without following links; an unoccupied path's real access error must escape.
fn occupied_staging_file(path: &Path, error: &std::io::Error) -> bool {
    error.kind() == std::io::ErrorKind::AlreadyExists
        || (error.kind() == std::io::ErrorKind::PermissionDenied
            && std::fs::symlink_metadata(path).is_ok())
}

/// A scratch directory removed when dropped.
pub(crate) struct TempDir(pub PathBuf);

impl TempDir {
    pub fn create(prefix: &str) -> std::io::Result<TempDir> {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.subsec_nanos());
        let path = std::env::temp_dir().join(format!("{prefix}{}-{nanos}", std::process::id()));
        std::fs::create_dir(&path)?;
        Ok(TempDir(path))
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[cfg(test)]
mod staging_file_tests {
    use super::*;
    use std::io::{Error, ErrorKind};
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn staging_permission_errors_are_collisions_only_for_occupied_names() {
        let root = TempDir::create("ms-stage-permission-").unwrap();
        let candidate = root.0.join("candidate");
        let denied = Error::from(ErrorKind::PermissionDenied);
        assert!(!occupied_staging_file(&candidate, &denied));
        std::fs::create_dir(&candidate).unwrap();
        assert!(occupied_staging_file(&candidate, &denied));
        assert!(!occupied_staging_file(
            &candidate,
            &Error::from(ErrorKind::Other)
        ));
        std::fs::remove_dir(&candidate).unwrap();
        std::fs::write(&candidate, b"preserve this file").unwrap();
        assert!(occupied_staging_file(&candidate, &denied));
        assert_eq!(std::fs::read(&candidate).unwrap(), b"preserve this file");
    }

    #[test]
    fn metadata_staging_skips_occupied_directories_without_changing_them() {
        let root = TempDir::create("ms-metadata-directory-").unwrap();
        let output = root.0.join("program");
        let occupied = root
            .0
            .join(format!(".ms-metadata-{}-0.json", std::process::id()));
        std::fs::create_dir(&occupied).unwrap();
        std::fs::write(occupied.join("sentinel"), b"preserve this directory").unwrap();
        let next = AtomicUsize::new(0);
        write_metadata_with(
            &output,
            BuildType::Debug,
            ms_build::Backend::Cranelift,
            &next,
        )
        .unwrap();
        assert_eq!(next.load(Ordering::Relaxed), 2);
        assert_eq!(
            std::fs::read(occupied.join("sentinel")).unwrap(),
            b"preserve this directory"
        );
        let metadata = std::fs::read_to_string(root.0.join("program.ms-build.json")).unwrap();
        assert!(metadata.contains("\"format\": 1"), "{metadata}");
        assert_eq!(std::fs::read_dir(&root.0).unwrap().count(), 2);
    }
}
