//! A runtime fault or failed test as structured data, read from the record the native runtime
//! writes to the file named by `MS_FAULT_RECORD` just before the program exits.
//!
//! The runtime runs every registered cleanup before it writes the record, so a fault read from
//! one always ran its cleanups. The human text on standard error is not parsed: when a program
//! ends in a fault without a record (killed, or the runtime could not write the file), the
//! text becomes the message with no trace.

use crate::json::Json;
use ms_rt_abi::record::{self, FaultKind, Record};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU32, Ordering};

/// The exit status of a program that ended in a runtime fault.
pub use ms_rt_abi::EXIT_FAULT;

/// The file a child process reports its fault or test failure in; removed when dropped.
pub struct RecordFile {
    path: PathBuf,
}

impl RecordFile {
    pub fn create() -> RecordFile {
        static NEXT: AtomicU32 = AtomicU32::new(0);
        let name = format!(
            "ms-fault-{}-{}.bin",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        );
        RecordFile {
            path: std::env::temp_dir().join(name),
        }
    }

    /// Names the file in the environment of `command`.
    pub fn attach(&self, command: &mut std::process::Command) {
        command.env(record::RECORD_ENV, &self.path);
    }

    /// The record the child process `pid` wrote, if it wrote one.
    pub fn read(&self, pid: u32) -> Option<Record> {
        let record = Record::decode(&std::fs::read(&self.path).ok()?)?;
        (record.pid == pid).then_some(record)
    }
}

impl Drop for RecordFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

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
    /// The fault a record describes.
    pub fn from_record(record: Record) -> Fault {
        let text = |bytes: Vec<u8>| String::from_utf8_lossy(&bytes).into_owned();
        Fault {
            kind: record.kind.name(),
            message: text(record.message),
            trace: record
                .frames
                .into_iter()
                .map(|frame| Frame {
                    file: frame.file,
                    line: frame.line as usize,
                    function: frame.function,
                    repeated: frame.repeated as usize,
                })
                .collect(),
            trace_truncated: record.truncated,
            cleanup_faults: record.cleanup_faults.into_iter().map(text).collect(),
        }
    }

    /// A fault with only the text the program printed, for an exit without a record.
    pub fn from_text(text: &str) -> Option<Fault> {
        let text = text.trim_end_matches('\n');
        (!text.is_empty()).then(|| Fault {
            kind: FaultKind::Fault.name(),
            message: text.to_string(),
            trace: Vec::new(),
            trace_truncated: false,
            cleanup_faults: Vec::new(),
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

#[cfg(test)]
mod tests {
    use super::*;
    use ms_rt_abi::record::Frame as RecordFrame;

    #[test]
    fn reads_message_trace_and_cleanup_faults() {
        let mut record = Record::new(
            FaultKind::DivisionByZero,
            b"division by zero; right must be nonzero, found 0",
        );
        record.frames.push(RecordFrame {
            file: "/w/main.ms".into(),
            line: 7,
            function: "divide".into(),
            repeated: 0,
        });
        record.frames.push(RecordFrame {
            file: "/w/main.ms".into(),
            line: 3,
            function: "main".into(),
            repeated: 4,
        });
        record.truncated = true;
        record.cleanup_faults.push(b"close failed\ndetail".to_vec());
        let fault = Fault::from_record(record);
        assert_eq!(fault.kind, "division_by_zero");
        assert_eq!(
            fault.message,
            "division by zero; right must be nonzero, found 0"
        );
        assert_eq!(fault.trace.len(), 2);
        assert_eq!(fault.trace[0].file, "/w/main.ms");
        assert_eq!(fault.trace[0].line, 7);
        assert_eq!(fault.trace[1].repeated, 4);
        assert!(fault.trace_truncated);
        assert_eq!(fault.cleanup_faults, ["close failed\ndetail"]);
    }

    #[test]
    fn empty_text_is_no_fault() {
        assert_eq!(Fault::from_text("\n"), None);
    }
}
