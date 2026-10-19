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
        Position { file: file.into(), line, column, offset: 0 }
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

/// One diagnostic: `{code, phase?, message, position, end?, fix?}`.
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
        CommandDiagnostic { code: code_for(phase, message), phase: phase.into(), message: message.into(), position, end: None, fix: None }
    }

    pub fn to_json(&self) -> Json {
        let mut object = Json::object().with("code", Json::str(&self.code));
        if !self.phase.is_empty() {
            object = object.with("phase", Json::str(&self.phase));
        }
        object = object.with("message", Json::str(&self.message)).with("position", self.position.to_json());
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
    Json::object().with("format", Json::int(1)).with("diagnostics", Json::Arr(diagnostics.iter().map(CommandDiagnostic::to_json).collect()))
}

/// The stable rule family for a source diagnostic (`Diagnostic.Code` in Go).
pub fn code_for(phase: &str, message: &str) -> String {
    // Messages read "<cause>; <fix>". Only the cause identifies the rule.
    let message = message.split("; ").next().unwrap_or("");
    let has = |needle: &str| message.contains(needle);
    let code = match phase {
        "parse" => {
            if message.starts_with("string-literal match patterns") {
                "MS1000"
            } else if has("indent") || has("suite") || has("tabs") {
                "MS1002"
            } else if has("UTF-8") || has("scalar") || has("escape") || has("literal") {
                "MS1001"
            } else {
                "MS1000"
            }
        }
        "resolution" => {
            if message.starts_with("redundant prelude import ") {
                "MS2003"
            } else if has("module") || has("import") || has("path") || has("alias") {
                "MS2002"
            } else {
                "MS2001"
            }
        }
        "type" => {
            const RULES: [(&str, &str); 16] = [
                ("duplicate argument", "MS3002"),
                ("missing argument", "MS3003"),
                ("unknown argument", "MS3004"),
                ("overlapping implementation", "MS3010"),
                ("signature does not match", "MS3011"),
                ("nominal source data", "MS3012"),
                ("Hashable", "MS3021"),
                ("captured", "MS3030"),
                ("recursive", "MS3040"),
                ("exhaustive", "MS3050"),
                ("immutable", "MS3060"),
                ("literal", "MS3070"),
                ("infer", "MS3080"),
                ("generic arity", "MS3080"),
                ("expected ", "MS3001"),
                ("same independently known type", "MS3001"),
            ];
            RULES.iter().find(|(needle, _)| has(needle)).map_or("MS3000", |(_, code)| code)
        }
        "lowering" => "MS4000",
        _ => "MS0000",
    };
    code.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes() {
        assert_eq!(code_for("resolution", "unknown import alias @x; fix"), "MS2002");
        assert_eq!(code_for("resolution", "line too long; keep"), "MS2001");
        assert_eq!(code_for("type", "expected Int"), "MS3001");
        assert_eq!(code_for("parse", "bad indent"), "MS1002");
        assert_eq!(code_for("other", ""), "MS0000");
    }
}
