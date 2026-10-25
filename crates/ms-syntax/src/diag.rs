//! Diagnostics: the information a diagnostic carries.

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
///. Absence of a fix means human judgment is
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

    /// Stable rule family code (`MS1000`, ...).
    pub fn code(&self) -> &'static str {
        code_for(self.phase.as_str(), &self.message)
    }

    /// JSON object in the shape of the CLI's JSON diagnostics, indented by
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

/// The stable rule family for a source diagnostic.
pub fn code_for(phase: &str, message: &str) -> &'static str {
    // Messages read "<cause>; <fix>". Only the cause identifies the rule, not a
    // trailing " (in <use site>)" context.
    let message = message
        .split("; ")
        .next()
        .and_then(|cause| cause.split(" (in ").next())
        .unwrap_or("");
    let has = |needle: &str| message.contains(needle);
    match phase {
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
            RULES
                .iter()
                .find(|(needle, _)| has(needle))
                .map_or("MS3000", |(_, code)| code)
        }
        "lowering" => "MS4000",
        _ => "MS0000",
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

/// Appends `text` as a JSON string, escaping like standard JSON encoders
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

#[cfg(test)]
mod code_tests {
    use super::code_for;

    #[test]
    fn codes() {
        assert_eq!(
            code_for("resolution", "unknown import alias @x; fix"),
            "MS2002"
        );
        assert_eq!(code_for("resolution", "line too long; keep"), "MS2001");
        assert_eq!(code_for("type", "expected Int"), "MS3001");
        assert_eq!(code_for("parse", "bad indent"), "MS1002");
        assert_eq!(code_for("other", ""), "MS0000");
    }
}
