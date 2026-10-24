//! A runtime fault as structured data, parsed from the report the native runtime writes to
//! standard error when it exits with `EXIT_FAULT`.
//!
//! The report is the message, then `  at file:line in function` frames (innermost first, with
//! `... previous frame repeated N more times` and `... outer frames omitted` notes), then one
//! `cleanup fault: <message>` per fault raised while cleanups ran. The runtime runs every
//! registered cleanup before it writes the report, so a parsed fault always ran its cleanups.

use crate::json::Json;

/// The exit status of a program that ended in a runtime fault.
pub const EXIT_FAULT: i32 = 70;

#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    pub file: String,
    pub line: usize,
    pub function: String,
    /// How many further identical frames the report collapsed into this one.
    pub repeated: usize,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Fault {
    pub kind: &'static str,
    pub message: String,
    pub trace: Vec<Frame>,
    pub trace_truncated: bool,
    pub cleanup_faults: Vec<String>,
}

impl Fault {
    /// Parses a fault report; `None` when `report` is empty.
    pub fn parse(report: &str) -> Option<Fault> {
        let report = report.trim_end_matches('\n');
        if report.is_empty() {
            return None;
        }
        let (mut message, mut trace, mut truncated) = (Vec::new(), Vec::new(), false);
        let mut cleanup_faults: Vec<String> = Vec::new();
        for line in report.split('\n') {
            if let Some(text) = line.strip_prefix("cleanup fault: ") {
                cleanup_faults.push(text.to_string());
            } else if let Some(frame) = line.strip_prefix("  at ").and_then(parse_frame) {
                trace.push(frame);
            } else if let Some(count) = line
                .strip_prefix("  ... previous frame repeated ")
                .and_then(|rest| rest.strip_suffix(" more times"))
                .and_then(|n| n.parse().ok())
            {
                if let Some(last) = trace.last_mut() {
                    last.repeated = count;
                }
            } else if line == "  ... outer frames omitted" {
                truncated = true;
            } else if let Some(last) = cleanup_faults.last_mut() {
                last.push('\n');
                last.push_str(line);
            } else {
                message.push(line);
            }
        }
        let message = message.join("\n");
        Some(Fault {
            kind: kind_of(&message),
            message,
            trace,
            trace_truncated: truncated,
            cleanup_faults,
        })
    }

    pub fn to_json(&self) -> Json {
        let trace = self.trace.iter().map(|frame| {
            let mut item = Json::object()
                .with("function", Json::str(&frame.function))
                .with("file", Json::str(&frame.file))
                .with("line", Json::int(frame.line as i64));
            if frame.repeated > 0 {
                item = item.with("repeated", Json::int(frame.repeated as i64));
            }
            item
        });
        let mut fault = Json::object()
            .with("kind", Json::str(self.kind))
            .with("message", Json::str(&self.message));
        if let Some(top) = self.trace.first() {
            fault = fault.with(
                "position",
                Json::object()
                    .with("file", Json::str(&top.file))
                    .with("line", Json::int(top.line as i64)),
            );
        }
        fault
            .with("trace", Json::Arr(trace.collect()))
            .with("trace_truncated", Json::Bool(self.trace_truncated))
            .with("cleanups_ran", Json::Bool(true))
            .with(
                "cleanup_faults",
                Json::Arr(self.cleanup_faults.iter().map(Json::str).collect()),
            )
            .with("exit_code", Json::int(i64::from(EXIT_FAULT)))
    }
}

/// `file:line in function`, split from the right because file names may hold colons.
fn parse_frame(text: &str) -> Option<Frame> {
    let (place, function) = text.split_once(" in ")?;
    let (file, line) = place.rsplit_once(':')?;
    Some(Frame {
        file: file.to_string(),
        line: line.parse().ok()?,
        function: function.to_string(),
        repeated: 0,
    })
}

/// A stable name for the family of fault a message belongs to.
fn kind_of(message: &str) -> &'static str {
    let contains = |s: &str| message.contains(s);
    if message.starts_with("incomplete cleanup") {
        "incomplete_cleanup"
    } else if message.starts_with("stack overflow") {
        "stack_overflow"
    } else if message.starts_with("deadlock") {
        "deadlock"
    } else if contains("division by zero") {
        "division_by_zero"
    } else if contains("overflow") {
        "overflow"
    } else if contains("out of range") || contains("index must be between") {
        "index_out_of_range"
    } else if message.starts_with("expected ") || message.starts_with("expect") {
        "assertion"
    } else {
        "fault"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_message_trace_and_cleanup_faults() {
        let report = "Int./: division by zero; right must be nonzero, found 0\n  at /w/main.ms:7 in divide\n  at /w/main.ms:3 in main\n  ... previous frame repeated 4 more times\n  ... outer frames omitted\ncleanup fault: close failed\ndetail";
        let fault = Fault::parse(report).unwrap();
        assert_eq!(fault.kind, "division_by_zero");
        assert_eq!(
            fault.message,
            "Int./: division by zero; right must be nonzero, found 0"
        );
        assert_eq!(fault.trace.len(), 2);
        assert_eq!(fault.trace[0].file, "/w/main.ms");
        assert_eq!(fault.trace[0].line, 7);
        assert_eq!(fault.trace[1].repeated, 4);
        assert!(fault.trace_truncated);
        assert_eq!(fault.cleanup_faults, ["close failed\ndetail"]);
    }

    #[test]
    fn empty_report_is_no_fault() {
        assert_eq!(Fault::parse("\n"), None);
    }
}
