//! The Rust engine behind `ms build`, `ms run`, `ms test` (and, through them,
//! `ms profile`): source to Cranelift-compiled native executable.
//!
//! ```text
//! ms_driver::load_file -> check_graph -> Lower -> optimize -> ms-clif -> link with ms-native
//! ```
//!
//! [`RustBackend`] is generic over the [`Lower`] stage so the CLI does not
//! depend on HIR to MIR lowering landing, and tests can inject a lowering.
//! Commands that this engine does not serve keep the trait's "not yet
//! implemented" default.

mod build;
mod run;
mod runtime;
mod search;
pub mod testing;
mod tooling;
mod watch;

use std::path::{Path, PathBuf};

use ms_driver::{
    CheckRequest, Diagnostic, Graph, LoadOptions, Lower, LowerOptions, Phase, Pos, check_graph,
    load_file,
};

use crate::backend::{
    AnalysisRequest, Backend, BackendError, BackendResult, BuildRequest, BuildType, DiagramRequest,
    FormatFailure, FormatFile, Io, OutputRequest, ReviewRequest, RunRequest, SearchSymbolRequest,
    TestRequest,
};
use crate::diagnostic::{CommandDiagnostic, Position};
use crate::json::Json;
use crate::util::plural;

/// The `ms` engine for native builds. `L` turns a checked program into MIR.
pub struct RustBackend<L: Lower> {
    pub lowering: L,
    /// The native static library to link; `MS_RT_LIB`, then the archive
    /// embedded in `ms` (see [`runtime`]), when unset.
    pub runtime: Option<PathBuf>,
}

impl<L: Lower> RustBackend<L> {
    pub fn new(lowering: L) -> RustBackend<L> {
        RustBackend {
            lowering,
            runtime: None,
        }
    }

    /// Link against `runtime` instead of searching for it.
    pub fn with_runtime(mut self, runtime: impl Into<PathBuf>) -> RustBackend<L> {
        self.runtime = Some(runtime.into());
        self
    }

    /// Compile the lowered module into the executable `output`.
    pub(crate) fn link(
        &self,
        compiled: &mut Compiled,
        output: &Path,
        kind: BuildType,
    ) -> Result<(), String> {
        let runtime = match &self.runtime {
            Some(runtime) => runtime.clone(),
            None => match ms_driver::runtime_override()? {
                Some(runtime) => runtime,
                None => runtime::embedded()?,
            },
        };
        ms_driver::build_executable(&mut compiled.module, output, profile(kind), &runtime)?;
        write_metadata(output, kind);
        Ok(())
    }
}

impl<L: Lower> Backend for RustBackend<L> {
    fn build(&self, request: &BuildRequest, io: &mut Io) -> BackendResult {
        build::build(self, request, io)
    }

    fn run(&self, request: &RunRequest, io: &mut Io) -> BackendResult {
        if request.watch {
            return watch::run(self, request, io);
        }
        run::run(self, request, io)
    }

    fn test(&self, request: &TestRequest, io: &mut Io) -> BackendResult {
        if request.watch {
            return watch::test(self, request, io);
        }
        testing::test(self, request, io)
    }

    fn check(&self, request: &AnalysisRequest, io: &mut Io) -> BackendResult {
        tooling::analysis(request, io)
    }

    fn lint(&self, request: &AnalysisRequest, io: &mut Io) -> BackendResult {
        tooling::analysis(request, io)
    }

    fn emit(&self, request: &OutputRequest, io: &mut Io) -> BackendResult {
        let compiled = match compile(self, &request.filename, BuildType::Release, false) {
            Ok(compiled) => compiled,
            Err(failure) => return Ok(failure.report(io)),
        };
        let text = ms_mir::print::print_module(&compiled.module);
        Ok(crate::util::write_output(
            io,
            &request.output,
            text.as_bytes(),
        ))
    }

    fn inspect(&self, request: &OutputRequest, io: &mut Io) -> BackendResult {
        tooling::inspect_command(request, io)
    }

    fn diagram(&self, request: &DiagramRequest, io: &mut Io) -> BackendResult {
        tooling::diagram(request, io)
    }

    fn review(&self, request: &ReviewRequest, io: &mut Io) -> BackendResult {
        tooling::review(request, io)
    }

    fn format_source(&self, file: &FormatFile, source: &str) -> Result<String, FormatFailure> {
        tooling::format_source(file, source)
    }

    fn search_symbol(&self, request: &SearchSymbolRequest, io: &mut Io) -> BackendResult {
        search::search_symbol(request, io)
    }

    fn guide(&self, io: &mut Io) -> BackendResult {
        let _ = write!(io.stdout, "{}", ms_guide::cheatsheet());
        Ok(0)
    }

    fn drop_redundant_labels(
        &self,
        file: &FormatFile,
        source: &str,
    ) -> Result<String, FormatFailure> {
        tooling::drop_redundant_labels(file, source)
    }

    /// The server reads the process stdin itself: the supervisor's reader runs
    /// on its own thread and needs a `'static` stream.
    fn lsp(&self, io: &mut Io) -> BackendResult {
        let served = if std::env::var_os(LSP_WORKER).is_some() {
            ms_lsp::serve(std::io::stdin(), &mut *io.stdout)
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
            Err(message) => Err(BackendError::Failed(format!("ms lsp: {message}"))),
        }
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
        for issue in self.in_source_order() {
            let mut issue = issue.clone();
            if !self.source_root.is_empty() && !issue.file.starts_with('/') {
                issue.file = format!("{}/{}", self.source_root, issue.file).into();
            }
            let _ = writeln!(io.stderr, "{issue}");
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
    let position = |pos: Pos| Position {
        file: issue.file.to_string(),
        line: pos.line as usize,
        column: pos.column as usize,
        offset: pos.offset as usize,
    };
    CommandDiagnostic {
        code: issue.code().to_string(),
        phase: issue.phase.as_str().to_string(),
        message: issue.message.clone(),
        position: position(issue.pos),
        end: issue.end.map(position),
        fix: issue.fix.as_ref().map(|fix| {
            Json::object()
                .with("position", position(fix.pos).to_json())
                .with("end", position(fix.end).to_json())
                .with("replacement", Json::str(&fix.replacement))
        }),
    }
}

/// A checked and lowered program.
pub(crate) struct Compiled {
    pub module: ms_driver::Module,
    /// Full `module::name` identities in index order (test executables only).
    pub tests: Vec<String>,
    pub source_root: String,
    pub project_root: String,
}

/// Load, check and lower `filename` for an executable (`tests == false`) or a
/// test executable.
pub(crate) fn compile<L: Lower>(
    backend: &RustBackend<L>,
    filename: &str,
    kind: BuildType,
    tests: bool,
) -> Result<Compiled, Failure> {
    let graph = load_file(filename, LoadOptions { tests });
    let library = graph.library;
    let project = !graph.project_root.is_empty();
    if project && library && !tests {
        return Err(library_failure(&graph));
    }
    let entry_required = !tests && (!project || !library);
    let entry = graph.entry.clone();
    let checked = check_graph(
        graph,
        CheckRequest {
            entry: entry_required,
            ..CheckRequest::default()
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
    let options = LowerOptions {
        debug: kind == BuildType::Debug,
    };
    let lowered = if tests {
        backend.lowering.lower_tests(program, &entry, &options)
    } else {
        backend
            .lowering
            .lower(program, &entry, &options)
            .map(|module| (module, Vec::new()))
    };
    match lowered {
        Ok((module, names)) => Ok(Compiled {
            module,
            tests: names,
            source_root: checked.source_root.clone(),
            project_root: checked.project_root.clone(),
        }),
        Err(message) => {
            let file = if entry.is_empty() { filename } else { &entry };
            Err(failure(
                vec![Diagnostic {
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
            file: file.as_str().into(),
            pos,
            phase: Phase::Resolution,
            message: "library project has no executable entry; add entry = \"src/main.ms\" under [project] and export fn main() Int from that file, or use check, lint, test, doc, or lock for the library".to_string(),
            end: None,
            fix: None,
        }],
    }
}

/// Map the CLI's build levels onto the code generator's.
pub(crate) fn profile(kind: BuildType) -> ms_driver::Profile {
    match kind {
        BuildType::Debug => ms_driver::Profile::Debug,
        BuildType::Release => ms_driver::Profile::Release,
        BuildType::RelWithDebInfo => ms_driver::Profile::RelWithDebInfo,
        BuildType::MinSizeRel => ms_driver::Profile::MinSizeRel,
    }
}

/// `<executable>.ms-build.json`: what built the executable.
fn write_metadata(output: &Path, kind: BuildType) {
    let mut name = output.as_os_str().to_owned();
    name.push(".ms-build.json");
    let document = format!(
        "{{\n  \"format\": 1,\n  \"version\": {},\n  \"backend\": \"cranelift\",\n  \"build_type\": \"{}\"\n}}\n",
        crate::quote(crate::VERSION),
        kind.as_str()
    );
    let _ = std::fs::write(PathBuf::from(name), document);
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
