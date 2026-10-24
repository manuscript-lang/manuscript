//! Request types and process streams shared by the command line and the engine.
//!
//! `ms-cli` owns everything a user can observe about *arguments*: dispatch,
//! option parsing and validation, help text, usage errors and exit statuses.
//! A command receives a validated request and the process streams, does the
//! work, writes its output (text or `--json`) to `io`, and returns the exit
//! status. Rendering helpers shared with the CLI output ([`crate::diagnostic`],
//! [`crate::json`], [`crate::util`]) are public.

use std::io::{Read, Write};

/// The process streams a command reads and writes. Streams are injectable so
/// `ms verify` can capture a step and tests can run the CLI in process.
pub struct Io<'a> {
    pub stdin: &'a mut dyn Read,
    pub stdout: &'a mut dyn Write,
    pub stderr: &'a mut dyn Write,
}

/// A command that failed; the message goes to stderr and the status is 1.
#[derive(Debug)]
pub struct BackendError(pub String);

/// `Ok(status)` is the exit status the command returns.
pub type BackendResult = Result<i32, BackendError>;

/// The native build levels, in the CMake spelling (parsed case-insensitively).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BuildType {
    Debug,
    Release,
    MinSizeRel,
}

impl BuildType {
    pub fn as_str(self) -> &'static str {
        match self {
            BuildType::Debug => "Debug",
            BuildType::Release => "Release",
            BuildType::MinSizeRel => "MinSizeRel",
        }
    }

    /// Empty means Release, like `compiler.ParseBuildType`.
    pub fn parse(name: &str) -> Result<BuildType, String> {
        if name.is_empty() {
            return Ok(BuildType::Release);
        }
        [BuildType::Debug, BuildType::Release, BuildType::MinSizeRel]
            .into_iter()
            .find(|kind| kind.as_str().eq_ignore_ascii_case(name))
            .ok_or_else(|| {
                format!("unknown build type {name:?}; expected Debug, Release, or MinSizeRel")
            })
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
    /// Extra objects and static libraries to link (`--link`).
    pub link: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct RunRequest {
    pub filename: String,
    pub build_type: BuildType,
    /// Extra objects and static libraries to link (`--link`).
    pub link: Vec<String>,
    pub watch: bool,
    /// Report the run as one JSON document, with a runtime fault as structured data.
    pub json: bool,
    /// Program arguments (everything after `--`).
    pub arguments: Vec<String>,
}

/// `ms test`. `arguments` is what is forwarded to the test executable: the
/// selection options (`--list`, `--fail-fast`, `--test=...`, `--match=...`,
/// `--exclude=...`, `--repeat=...`, `--shuffle=...`), then `--timeout=` and
/// `--filter=` when set, then the user's arguments after `--`.
#[derive(Clone, Debug)]
pub struct TestRequest {
    pub filename: String,
    pub build_type: BuildType,
    /// Extra objects and static libraries to link (`--link`).
    pub link: Vec<String>,
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
    Syntax(Box<crate::diagnostic::CommandDiagnostic>),
    /// Any other message (e.g. `--drop-labels` needs source that checks).
    Message(String),
}

/// Report a command's outcome on stderr and turn it into an exit status.
pub fn finish(result: BackendResult, io: &mut Io) -> i32 {
    match result {
        Ok(status) => status,
        Err(BackendError(message)) => {
            let _ = writeln!(io.stderr, "{message}");
            1
        }
    }
}
