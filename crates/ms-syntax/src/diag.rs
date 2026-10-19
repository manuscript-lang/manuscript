//! Diagnostics: the information `pkg/syntax.Diagnostic` carries.

use crate::pos::Pos;
use std::fmt;
use std::sync::Arc;

/// The compiler phase that produced a diagnostic. The JSON/terminal name is
/// [`Phase::as_str`].
#[derive(Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub enum Phase {
    /// Lexing and parsing (`"parse"`).
    Parse,
    /// Import and name resolution (`"resolution"`).
    Resolution,
    /// Type checking (`"type"`).
    Type,
    /// Lowering (`"lowering"`).
    Lowering,
    /// Formatting (`"format"`).
    Format,
    /// Execution (`"execution"`).
    Execution,
}

impl Phase {
    /// The phase name used in JSON and terminal output.
    pub fn as_str(self) -> &'static str {
        match self {
            Phase::Parse => "parse",
            Phase::Resolution => "resolution",
            Phase::Type => "type",
            Phase::Lowering => "lowering",
            Phase::Format => "format",
            Phase::Execution => "execution",
        }
    }
}

/// A machine-applicable replacement of one exact source range
/// (`pkg/syntax.DiagnosticFix`). Absence of a fix means human judgment is
/// required.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DiagnosticFix {
    /// Start of the replaced range.
    pub pos: Pos,
    /// Exclusive end of the replaced range.
    pub end: Pos,
    /// Text that replaces the range.
    pub replacement: String,
}

/// A source diagnostic. `pos.line == 0` is never produced by the parser.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Diagnostic {
    /// File the position refers to, as given to the parser.
    pub file: Arc<str>,
    /// Start position.
    pub pos: Pos,
    /// Producing phase.
    pub phase: Phase,
    /// Human-readable message; `"<cause>; <fix>"` by convention.
    pub message: String,
    /// Exclusive end of the range, when known.
    pub end: Option<Pos>,
    /// Machine-applicable fix, when one exists.
    pub fix: Option<DiagnosticFix>,
}

impl Diagnostic {
    /// A parse-phase diagnostic without a range.
    pub fn parse(file: &Arc<str>, pos: Pos, message: impl Into<String>) -> Diagnostic {
        Diagnostic {
            file: file.clone(),
            pos,
            phase: Phase::Parse,
            message: message.into(),
            end: None,
            fix: None,
        }
    }

    /// Stable rule family code (`MS1000`, ...), matching `Diagnostic.Code` in Go.
    pub fn code(&self) -> &'static str {
        // Messages read "<cause>; <fix>". Only the cause identifies the rule.
        let message = self.message.split("; ").next().unwrap_or("");
        match self.phase {
            Phase::Parse => {
                if message.starts_with("string-literal match patterns") {
                    "MS1000"
                } else if message.contains("indent")
                    || message.contains("suite")
                    || message.contains("tabs")
                {
                    "MS1002"
                } else if message.contains("UTF-8")
                    || message.contains("scalar")
                    || message.contains("escape")
                    || message.contains("literal")
                {
                    "MS1001"
                } else {
                    "MS1000"
                }
            }
            Phase::Resolution => {
                if message.starts_with("redundant prelude import ") {
                    "MS2003"
                } else if message.contains("module")
                    || message.contains("import")
                    || message.contains("path")
                    || message.contains("alias")
                {
                    "MS2002"
                } else {
                    "MS2001"
                }
            }
            Phase::Type => {
                const RULES: &[(&str, &str)] = &[
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
                for (needle, code) in RULES {
                    if message.contains(needle) {
                        return code;
                    }
                }
                "MS3000"
            }
            Phase::Lowering => "MS4000",
            _ => "MS0000",
        }
    }

    /// JSON object in the shape of Go's `Diagnostic.MarshalJSON`, indented by
    /// `indent` levels of two spaces is left to the caller; this is compact.
    pub fn to_json(&self) -> String {
        let mut out = String::new();
        out.push_str("{\"code\":");
        json_string(&mut out, self.code());
        out.push_str(",\"phase\":");
        json_string(&mut out, self.phase.as_str());
        out.push_str(",\"message\":");
        json_string(&mut out, &self.message);
        out.push_str(",\"position\":");
        json_position(&mut out, &self.file, self.pos);
        if let Some(end) = self.end {
            out.push_str(",\"end\":");
            json_position(&mut out, &self.file, end);
        }
        if let Some(fix) = &self.fix {
            out.push_str(",\"fix\":{\"position\":");
            json_position(&mut out, &self.file, fix.pos);
            out.push_str(",\"end\":");
            json_position(&mut out, &self.file, fix.end);
            out.push_str(",\"replacement\":");
            json_string(&mut out, &fix.replacement);
            out.push('}');
        }
        out.push('}');
        out
    }
}

impl fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}:{}:{}: {}: {}",
            self.file,
            self.pos.line,
            self.pos.column,
            self.phase.as_str(),
            self.message
        )
    }
}

impl std::error::Error for Diagnostic {}

fn json_position(out: &mut String, file: &str, pos: Pos) {
    out.push_str("{\"file\":");
    json_string(out, file);
    out.push_str(&format!(
        ",\"line\":{},\"column\":{},\"offset\":{}}}",
        pos.line, pos.column, pos.offset
    ));
}

/// Appends `text` as a JSON string, escaping like Go's `encoding/json`
/// (HTML-sensitive characters are escaped as well).
pub fn json_string(out: &mut String, text: &str) {
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '<' => out.push_str("\\u003c"),
            '>' => out.push_str("\\u003e"),
            '&' => out.push_str("\\u0026"),
            '\u{2028}' => out.push_str("\\u2028"),
            '\u{2029}' => out.push_str("\\u2029"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}
