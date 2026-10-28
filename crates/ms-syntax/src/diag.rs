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

    /// Stable sub-code (`MS3000.1`) naming the cause within the rule family, when the
    /// message is a known one. The family code is [`Diagnostic::code`].
    pub fn subcode(&self) -> Option<&'static str> {
        kind_for(self.code(), &self.message).map(|k| k.info.code)
    }

    /// JSON object in the shape of the CLI's JSON diagnostics, indented by
    /// `indent` levels of two spaces is left to the caller; this is compact.
    pub fn to_json(&self) -> String {
        let mut out = String::new();
        out.push_str("{\"code\":");
        json_string(&mut out, self.code());
        if let Some(subcode) = self.subcode() {
            out.push_str(",\"subcode\":");
            json_string(&mut out, subcode);
        }
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

/// What a diagnostic code means and how it is usually repaired.
pub struct CodeInfo {
    pub code: &'static str,
    pub family: &'static str,
    pub repair: &'static str,
}

/// Every code `code_for` can return, in order.
pub const CODES: &[CodeInfo] = &[
    CodeInfo {
        code: "MS0000",
        family: "Unclassified diagnostic",
        repair: "read the message; it names the cause and the fix",
    },
    CodeInfo {
        code: "MS1000",
        family: "Grammar",
        repair: "follow the expected token the message names; block headers end with ':'",
    },
    CodeInfo {
        code: "MS1001",
        family: "Literals and text",
        repair: "fix the literal, escape or encoding the message names",
    },
    CodeInfo {
        code: "MS1002",
        family: "Layout",
        repair: "indent with four spaces and keep each suite aligned",
    },
    CodeInfo {
        code: "MS2001",
        family: "Names and members",
        repair: "apply the `fix` edit (nearest name or import), or declare the name",
    },
    CodeInfo {
        code: "MS2002",
        family: "Modules and imports",
        repair: "check the path, extension and [aliases] entry the message names",
    },
    CodeInfo {
        code: "MS2003",
        family: "Redundant prelude import",
        repair: "delete the import; the prelude already provides it",
    },
    CodeInfo {
        code: "MS3000",
        family: "General typing",
        repair: "read the message; it names the rule and the fix",
    },
    CodeInfo {
        code: "MS3001",
        family: "Exact types and operators",
        repair: "convert explicitly: to_float(), \"{value}\", or an explicit comparison",
    },
    CodeInfo {
        code: "MS3002",
        family: "Duplicate argument",
        repair: "pass each argument once",
    },
    CodeInfo {
        code: "MS3003",
        family: "Missing argument",
        repair: "supply the parameter the message names",
    },
    CodeInfo {
        code: "MS3004",
        family: "Unknown argument",
        repair: "use one of the parameter names the message lists",
    },
    CodeInfo {
        code: "MS3010",
        family: "Overlapping implementation",
        repair: "keep one impl per interface and type",
    },
    CodeInfo {
        code: "MS3011",
        family: "Signature mismatch",
        repair: "match the interface operation's signature",
    },
    CodeInfo {
        code: "MS3012",
        family: "Implementation receiver",
        repair: "implement interfaces for types you declare",
    },
    CodeInfo {
        code: "MS3021",
        family: "Hashing",
        repair: "use a Hashable key type",
    },
    CodeInfo {
        code: "MS3030",
        family: "Captures",
        repair: "capture a copy with .clone(), or finish using the value first",
    },
    CodeInfo {
        code: "MS3040",
        family: "Recursion",
        repair: "keep recursive types finite and generic arguments stable",
    },
    CodeInfo {
        code: "MS3050",
        family: "Exhaustiveness",
        repair: "add the missing cases or a final `_:`",
    },
    CodeInfo {
        code: "MS3060",
        family: "Mutation",
        repair: "declare the binding with `var`; the `fix` edit rewrites `let`",
    },
    CodeInfo {
        code: "MS3070",
        family: "Numeric literals",
        repair: "use a value inside the type's range",
    },
    CodeInfo {
        code: "MS3080",
        family: "Generic inference",
        repair: "write the type arguments or annotate the binding",
    },
    CodeInfo {
        code: "MS4000",
        family: "Lowering",
        repair: "report this as a compiler bug with the source",
    },
];

/// One cause within a rule family: a stable sub-code, recognized by the opening words of the
/// message's cause. Numbers are never reused; retire a number rather than renumbering.
pub struct Kind {
    /// The family code the message must already carry.
    pub family: &'static str,
    /// The message cause contains this text.
    pub needle: &'static str,
    /// The sub-code, its name, and its repair.
    pub info: CodeInfo,
}

macro_rules! kind {
    ($family:literal, $code:literal, $needle:literal, $name:literal, $repair:literal) => {
        Kind {
            family: $family,
            needle: $needle,
            info: CodeInfo {
                code: $code,
                family: $name,
                repair: $repair,
            },
        }
    };
}

/// Every sub-code, grouped by family. A message without an entry keeps its family code only.
pub const KINDS: &[Kind] = &[
    kind!(
        "MS2001",
        "MS2001.1",
        "unknown binding",
        "Unknown name",
        "apply the `fix` edit, import the name, or declare it"
    ),
    kind!(
        "MS2001",
        "MS2001.2",
        "unknown type",
        "Unknown type",
        "import the type or declare it"
    ),
    kind!(
        "MS2001",
        "MS2001.3",
        "unknown or ambiguous member",
        "Unknown member",
        "use one of the members the message lists"
    ),
    kind!(
        "MS2001",
        "MS2001.4",
        "unknown case",
        "Unknown alternative case",
        "name a case the alternative declares"
    ),
    kind!(
        "MS2001",
        "MS2001.5",
        "reuses a prelude name",
        "Prelude name reused",
        "rename the declaration"
    ),
    kind!(
        "MS2001",
        "MS2001.6",
        "fixture is available only",
        "Fixture outside tests",
        "declare a make_fixture factory in the test module"
    ),
    kind!(
        "MS2002",
        "MS2002.1",
        "unknown standard module",
        "Unknown standard module",
        "check the module name against the standard library"
    ),
    kind!(
        "MS3000",
        "MS3000.1",
        "is never read",
        "Unused local binding",
        "use the binding, or name it with a leading '_'"
    ),
    kind!(
        "MS3000",
        "MS3000.2",
        "is moved here but used again",
        "Use after move",
        "pass `.clone()` to keep the value, or stop using it after the move"
    ),
    kind!(
        "MS3000",
        "MS3000.3",
        "returns part of a parameter",
        "Result borrows a parameter",
        "write `ref` before the result type, or return an owned copy"
    ),
    kind!(
        "MS3000",
        "MS3000.4",
        "shadows an outer binding",
        "Shadowed binding",
        "rename one binding, or assign to the outer `var`"
    ),
    kind!(
        "MS3000",
        "MS3000.5",
        "this statement discards",
        "Discarded Result",
        "write `try ...` to propagate the failure, or handle it"
    ),
    kind!(
        "MS3000",
        "MS3000.6",
        "reachable fallthrough",
        "Missing return",
        "return a value on every path"
    ),
    kind!(
        "MS3000",
        "MS3000.7",
        "division by zero",
        "Division by zero",
        "divide by a nonzero value"
    ),
    kind!(
        "MS3000",
        "MS3000.8",
        "does not satisfy",
        "Bound not satisfied",
        "use a type that implements the interface"
    ),
    kind!(
        "MS3000",
        "MS3000.9",
        "cannot be constructed",
        "Interface constructed",
        "construct a type that implements the interface"
    ),
    kind!(
        "MS3000",
        "MS3000.10",
        "is a resource that is never closed",
        "Unclosed resource",
        "open it with `with let`, call `.close()`, or return it"
    ),
    kind!(
        "MS3000",
        "MS3000.11",
        "cannot move ",
        "Move out of a borrow",
        "take an owned copy with `.clone()`"
    ),
    kind!(
        "MS3000",
        "MS3000.12",
        "requires a record field",
        "Assignment target",
        "assign to a record field or a variable"
    ),
    kind!(
        "MS3000",
        "MS3000.13",
        "with needs a Closeable",
        "With needs a resource",
        "bind a value with `close() Unit`"
    ),
    kind!(
        "MS3001",
        "MS3001.1",
        "expected ",
        "Type mismatch",
        "convert explicitly, or change the declared type"
    ),
    kind!(
        "MS3010",
        "MS3010.1",
        "overlapping implementation",
        "Overlapping implementation",
        "keep one impl per interface and type"
    ),
    kind!(
        "MS3011",
        "MS3011.1",
        "signature does not match",
        "Signature mismatch",
        "match the interface operation's signature"
    ),
    kind!(
        "MS3000",
        "MS3000.14",
        "missing implementation operation",
        "Missing operation",
        "implement every operation the interface declares"
    ),
    kind!(
        "MS3000",
        "MS3000.15",
        "extra operation",
        "Extra operation",
        "remove operations the interface does not declare"
    ),
    kind!(
        "MS3000",
        "MS3000.16",
        "duplicate implementation operation",
        "Duplicate operation",
        "define each operation once"
    ),
    kind!(
        "MS3012",
        "MS3012.1",
        "implementation receiver must be nominal",
        "Implementation receiver",
        "implement interfaces for a type or alternative you declare"
    ),
    kind!(
        "MS3000",
        "MS3000.17",
        "implementation target must be an interface",
        "Implementation target",
        "name an interface after `impl`"
    ),
    kind!(
        "MS3050",
        "MS3050.1",
        "exhaustive",
        "Non-exhaustive match",
        "add the missing cases or a final `_:`"
    ),
    kind!(
        "MS3000",
        "MS3000.18",
        "parameter",
        "Parameter not declared var",
        "write `var` before the parameter"
    ),
    kind!(
        "MS3060",
        "MS3060.2",
        "declared with let",
        "Binding declared with let",
        "declare the binding with `var`"
    ),
    kind!(
        "MS3000",
        "MS3000.19",
        "does not change its receiver",
        "Method does not change its receiver",
        "declare the method `var fn`"
    ),
    kind!(
        "MS3080",
        "MS3080.1",
        "cannot infer",
        "Cannot infer",
        "write the type arguments or annotate the binding"
    ),
    kind!(
        "MS3000",
        "MS3000.20",
        "type arguments, found ",
        "Generic arity",
        "write every required type argument"
    ),
];

/// The first sub-code of `family` whose needle appears in the message's cause.
pub fn kind_for(family: &str, message: &str) -> Option<&'static Kind> {
    let cause = message.split("; ").next().unwrap_or("");
    KINDS
        .iter()
        .find(|k| k.family == family && cause.contains(k.needle))
}

/// The entry for `code` or a sub-code, matched case-insensitively.
pub fn explain(code: &str) -> Option<&'static CodeInfo> {
    CODES
        .iter()
        .chain(KINDS.iter().map(|k| &k.info))
        .find(|c| c.code.eq_ignore_ascii_case(code))
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
    fn every_returned_code_is_explained() {
        for (phase, message) in [
            ("parse", ""),
            ("parse", "indent"),
            ("parse", "UTF-8"),
            ("resolution", "unknown"),
            ("resolution", "module"),
            ("type", ""),
        ] {
            assert!(super::explain(super::code_for(phase, message)).is_some());
        }
        assert!(super::explain("ms3060").is_some());
        assert!(super::explain("MS9999").is_none());
    }

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
