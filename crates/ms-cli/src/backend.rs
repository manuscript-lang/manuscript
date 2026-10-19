//! The engine boundary of the command line.
//!
//! `ms-cli` owns everything a user can observe about *arguments*: dispatch,
//! option parsing and validation, help text, usage errors and exit statuses.
//! The compiler engines (parser, checker, MIR, Cranelift, linker, runtime,
//! tooling) plug in by implementing [`Backend`]. Every method has a default
//! that reports "not yet implemented in the Rust implementation" and exits with
//! [`EXIT_NOT_IMPLEMENTED`], so an engine session overrides exactly the
//! commands it can serve and the rest keep failing loudly.
//!
//! A backend method receives a validated request and the process streams, does
//! the work, writes the command's output (text or `--json`) to `io`, and
//! returns the exit status. Rendering helpers shared with the Go-compatible
//! output ([`crate::diagnostic`], [`crate::json`], [`crate::util`]) are public.

use std::io::{Read, Write};

/// Exit status for a command whose engine is not available yet. It is distinct
/// from every status the Go `ms` uses (0 success, 1 failure, 2 usage error) and
/// from the 126/127 shell statuses, so scripts and the differential tests can
/// tell "not implemented" from "failed".
pub const EXIT_NOT_IMPLEMENTED: i32 = 70;

/// The process streams a command reads and writes. Streams are injectable so
/// `ms verify` can capture a step and tests can run the CLI in process.
pub struct Io<'a> {
    pub stdin: &'a mut dyn Read,
    pub stdout: &'a mut dyn Write,
    pub stderr: &'a mut dyn Write,
}

/// How a backend call ends.
#[derive(Debug)]
pub enum BackendError {
    /// The engine for this command does not exist yet.
    NotImplemented(&'static str),
    /// The command failed; the message goes to stderr and the status is 1.
    Failed(String),
}

/// `Ok(status)` is the exit status the command returns.
pub type BackendResult = Result<i32, BackendError>;

/// The native build levels, in the CMake spelling (parsed case-insensitively).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BuildType {
    Debug,
    Release,
    RelWithDebInfo,
    MinSizeRel,
}

impl BuildType {
    pub fn as_str(self) -> &'static str {
        match self {
            BuildType::Debug => "Debug",
            BuildType::Release => "Release",
            BuildType::RelWithDebInfo => "RelWithDebInfo",
            BuildType::MinSizeRel => "MinSizeRel",
        }
    }

    /// Empty means Release, like `compiler.ParseBuildType`.
    pub fn parse(name: &str) -> Result<BuildType, String> {
        if name.is_empty() {
            return Ok(BuildType::Release);
        }
        [BuildType::Debug, BuildType::Release, BuildType::RelWithDebInfo, BuildType::MinSizeRel]
            .into_iter()
            .find(|kind| kind.as_str().eq_ignore_ascii_case(name))
            .ok_or_else(|| format!("unknown build type {name:?}; expected Debug, Release, RelWithDebInfo, or MinSizeRel"))
    }
}

/// `ms check` or `ms lint`: independent compiler requests, never one program.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AnalysisCommand {
    Check,
    Lint,
}

impl AnalysisCommand {
    pub fn name(self) -> &'static str {
        match self {
            AnalysisCommand::Check => "check",
            AnalysisCommand::Lint => "lint",
        }
    }
}

#[derive(Clone, Debug)]
pub struct AnalysisRequest {
    pub command: AnalysisCommand,
    /// The targets as typed (files, directories, ms.toml).
    pub targets: Vec<String>,
    pub json: bool,
    pub watch: bool,
}

/// `ms build <input> [-o output]`. `output` is empty for the default
/// (`./program`). `entry` is true: the program must export `main() Int`.
#[derive(Clone, Debug)]
pub struct BuildRequest {
    pub filename: String,
    pub output: String,
    pub build_type: BuildType,
    pub json: bool,
}

#[derive(Clone, Debug)]
pub struct RunRequest {
    pub filename: String,
    pub build_type: BuildType,
    pub watch: bool,
    /// Program arguments (everything after `--`).
    pub arguments: Vec<String>,
}

/// `ms test`. `arguments` is what Go forwards to the test executable: the
/// selection options (`--list`, `--fail-fast`, `--test=...`, `--match=...`,
/// `--exclude=...`, `--repeat=...`, `--shuffle=...`), then `--timeout=` and
/// `--filter=` when set, then the user's arguments after `--`.
#[derive(Clone, Debug)]
pub struct TestRequest {
    pub filename: String,
    pub build_type: BuildType,
    pub json: bool,
    pub watch: bool,
    pub arguments: Vec<String>,
}

/// `ms emit`, `ms inspect`: write a text artifact to `output` or stdout.
#[derive(Clone, Debug)]
pub struct OutputRequest {
    pub filename: String,
    pub output: String,
    pub json: bool,
}

#[derive(Clone, Debug)]
pub struct DiagramRequest {
    pub filename: String,
    pub output: String,
    /// `ascii` (default when empty) or `mermaid`.
    pub format: String,
    /// One of `calls effects errors modules flow scope`, or empty.
    pub view: String,
    pub entity: String,
    /// Zero means the default (3).
    pub depth: usize,
    /// A unified diff path, `-` for stdin, or empty.
    pub diff: String,
    pub json: bool,
}

#[derive(Clone, Debug)]
pub struct ReviewRequest {
    pub filename: String,
    pub diff: String,
    /// `ascii`, `markdown` or `json`.
    pub format: String,
    pub output: String,
    pub explain: String,
    pub all: bool,
}

#[derive(Clone, Debug)]
pub struct SearchSymbolRequest {
    /// Empty prints the standard-module index.
    pub names: Vec<String>,
    pub limit: usize,
    pub json: bool,
}

/// One `.ms` file selected by `ms fmt`, after target resolution and de-duplication.
#[derive(Clone, Debug)]
pub struct FormatFile {
    /// Canonical absolute path.
    pub path: String,
    /// The spelling used in messages and JSON (relative to the working directory when inside it).
    pub display: String,
}

/// Why formatting one file failed.
#[derive(Clone, Debug)]
pub enum FormatFailure {
    /// The source does not parse. The CLI wraps it with the
    /// "fmt only formats source that parses" hint.
    Syntax(crate::diagnostic::CommandDiagnostic),
    /// Any other message (e.g. `--drop-labels` needs source that checks).
    Message(String),
}

/// The engines behind the commands. All methods default to "not implemented".
pub trait Backend {
    /// The release version printed by `ms version`. Defaults to `.msversion`.
    fn version(&self) -> String {
        crate::VERSION.to_string()
    }

    fn check(&self, _request: &AnalysisRequest, _io: &mut Io) -> BackendResult {
        not_implemented("check")
    }
    fn lint(&self, _request: &AnalysisRequest, _io: &mut Io) -> BackendResult {
        not_implemented("lint")
    }
    /// Build a native executable at `request.output` (or `./program`).
    fn build(&self, _request: &BuildRequest, _io: &mut Io) -> BackendResult {
        not_implemented("build")
    }
    /// Build a temporary executable and run it; return the program's status.
    fn run(&self, _request: &RunRequest, _io: &mut Io) -> BackendResult {
        not_implemented("run")
    }
    fn test(&self, _request: &TestRequest, _io: &mut Io) -> BackendResult {
        not_implemented("test")
    }
    fn emit(&self, _request: &OutputRequest, _io: &mut Io) -> BackendResult {
        not_implemented("emit")
    }
    fn inspect(&self, _request: &OutputRequest, _io: &mut Io) -> BackendResult {
        not_implemented("inspect")
    }
    fn diagram(&self, _request: &DiagramRequest, _io: &mut Io) -> BackendResult {
        not_implemented("diagram")
    }
    fn review(&self, _request: &ReviewRequest, _io: &mut Io) -> BackendResult {
        not_implemented("review")
    }
    fn search_symbol(&self, _request: &SearchSymbolRequest, _io: &mut Io) -> BackendResult {
        not_implemented("search_symbol")
    }
    /// Print the language cheat sheet.
    fn guide(&self, _io: &mut Io) -> BackendResult {
        not_implemented("guide")
    }
    /// Serve the language server on the given streams until the client disconnects.
    fn lsp(&self, _io: &mut Io) -> BackendResult {
        not_implemented("lsp")
    }
    /// Format one file's text. Returns the formatted text.
    fn format_source(&self, _file: &FormatFile, _source: &str) -> Result<String, FormatFailure> {
        Err(FormatFailure::Message(not_implemented_message("fmt")))
    }
    /// Apply `--drop-labels` to source that checks, before formatting.
    fn drop_redundant_labels(&self, _file: &FormatFile, _source: &str) -> Result<String, FormatFailure> {
        Err(FormatFailure::Message(not_implemented_message("fmt --drop-labels")))
    }
}

pub fn not_implemented_message(what: &str) -> String {
    format!("ms {what}: not yet implemented in the Rust implementation; use the Go ms until its engine lands")
}

pub fn not_implemented(what: &'static str) -> BackendResult {
    Err(BackendError::NotImplemented(what))
}

/// A backend with no engines: every command that needs one fails with
/// [`EXIT_NOT_IMPLEMENTED`]. The `ms` binary uses it until engines are linked.
pub struct NoEngines;

impl Backend for NoEngines {}

/// Report a backend outcome on stderr and turn it into an exit status.
pub fn finish(result: BackendResult, io: &mut Io) -> i32 {
    match result {
        Ok(status) => status,
        Err(BackendError::NotImplemented(what)) => {
            let _ = writeln!(io.stderr, "{}", not_implemented_message(what));
            EXIT_NOT_IMPLEMENTED
        }
        Err(BackendError::Failed(message)) => {
            let _ = writeln!(io.stderr, "{message}");
            1
        }
    }
}
