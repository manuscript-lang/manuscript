//! The diagnostic shape shared by every command's `--json` output.

use std::fmt;

use crate::json::Json;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Position {
    pub file: String,
    pub line: usize,
    pub column: usize,
    pub offset: usize,
}

impl Position {
    pub fn new(file: impl Into<String>, line: usize, column: usize) -> Position {
        Position {
            file: file.into(),
            line,
            column,
            offset: 0,
        }
    }

    pub fn to_json(&self) -> Json {
        Json::object()
            .with("file", Json::str(&self.file))
            .with("line", Json::int(self.line as i64))
            .with("column", Json::int(self.column as i64))
            .with("offset", Json::int(self.offset as i64))
    }
}

impl fmt::Display for Position {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}:{}", self.file, self.line, self.column)
    }
}

/// One diagnostic: `{code, subcode?, phase?, message, position, end?, fix?}`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct CommandDiagnostic {
    pub code: String,
    pub phase: String,
    pub message: String,
    pub position: Position,
    pub end: Option<Position>,
    /// A pre-built `fix` object, passed through unchanged.
    pub fix: Option<Json>,
}

impl CommandDiagnostic {
    /// A source diagnostic whose code is derived from phase and message.
    pub fn source(phase: &str, message: &str, position: Position) -> CommandDiagnostic {
        CommandDiagnostic {
            code: ms_syntax::diag::code_for(phase, message).to_string(),
            phase: phase.into(),
            message: message.into(),
            position,
            end: None,
            fix: None,
        }
    }

    pub fn to_json(&self) -> Json {
        let mut object = Json::object().with("code", Json::str(&self.code));
        if let Some(kind) = ms_syntax::diag::kind_for(&self.code, &self.message) {
            object = object.with("subcode", Json::str(kind.info.code));
        }
        if !self.phase.is_empty() {
            object = object.with("phase", Json::str(&self.phase));
        }
        object = object
            .with("message", Json::str(&self.message))
            .with("position", self.position.to_json());
        if let Some(end) = &self.end {
            object = object.with("end", end.to_json());
        }
        if let Some(fix) = &self.fix {
            object = object.with("fix", fix.clone());
        }
        object
    }

    /// `file:line:column: phase: message`, the terminal rendering of a source diagnostic.
    pub fn rendered(&self) -> String {
        format!("{}: {}: {}", self.position, self.phase, self.message)
    }
}

/// `{format: 1, diagnostics: [...]}`, the document check, lint and every
/// failing source command share.
pub fn diagnostics_document(diagnostics: &[CommandDiagnostic]) -> Json {
    Json::object().with("format", Json::int(1)).with(
        "diagnostics",
        Json::Arr(diagnostics.iter().map(CommandDiagnostic::to_json).collect()),
    )
}
