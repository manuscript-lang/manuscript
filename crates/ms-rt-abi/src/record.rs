//! The structured fault record: what a program that ended in a runtime fault or a failed test
//! tells the CLI on a side channel, so the CLI never parses the human text on standard error.
//!
//! The CLI names a file in `MS_FAULT_RECORD` for the child; the runtime writes one [`Record`]
//! there just before it exits (`EXIT_FAULT` for a fault, 1 for a failed test) and still prints
//! the human text to standard error. The encoding is little endian: the magic, a version byte,
//! the kind code, a flags byte, then length-prefixed byte strings and counts.

use alloc::string::String;
use alloc::vec::Vec;

/// The environment variable naming the file the runtime writes the record to.
pub const RECORD_ENV: &str = "MS_FAULT_RECORD";

const MAGIC: &[u8; 4] = b"MSFR";
const VERSION: u8 = 1;
const TRUNCATED: u8 = 1;
const HAS_SITE: u8 = 2;

/// The family of a fault, chosen by the runtime entry point that raised it.
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FaultKind {
    /// Any fault without a more specific family.
    Fault = 0,
    IncompleteCleanup = 1,
    StackOverflow = 2,
    Deadlock = 3,
    DivisionByZero = 4,
    Overflow = 5,
    IndexOutOfRange = 6,
    /// A test expectation failed (not a fault: the test returned an error).
    TestFailure = 7,
}

impl FaultKind {
    pub fn from_code(code: u8) -> FaultKind {
        match code {
            1 => FaultKind::IncompleteCleanup,
            2 => FaultKind::StackOverflow,
            3 => FaultKind::Deadlock,
            4 => FaultKind::DivisionByZero,
            5 => FaultKind::Overflow,
            6 => FaultKind::IndexOutOfRange,
            7 => FaultKind::TestFailure,
            _ => FaultKind::Fault,
        }
    }

    /// The stable name the JSON reports use.
    pub fn name(self) -> &'static str {
        match self {
            FaultKind::Fault => "fault",
            FaultKind::IncompleteCleanup => "incomplete_cleanup",
            FaultKind::StackOverflow => "stack_overflow",
            FaultKind::Deadlock => "deadlock",
            FaultKind::DivisionByZero => "division_by_zero",
            FaultKind::Overflow => "overflow",
            FaultKind::IndexOutOfRange => "index_out_of_range",
            FaultKind::TestFailure => "test_failure",
        }
    }
}

/// One source frame, innermost first in [`Record::frames`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Frame {
    pub file: String,
    pub line: u32,
    pub function: String,
    /// How many further identical frames were collapsed into this one.
    pub repeated: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Record {
    /// The process that wrote the record; the CLI ignores a record a descendant left behind.
    pub pid: u32,
    pub kind: FaultKind,
    pub message: Vec<u8>,
    pub frames: Vec<Frame>,
    pub truncated: bool,
    /// The message of each fault raised while cleanups ran.
    pub cleanup_faults: Vec<Vec<u8>>,
    /// `file:line:column` of the failed expectation, for a [`FaultKind::TestFailure`].
    pub site: Option<Vec<u8>>,
}

fn put_bytes(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
    out.extend_from_slice(bytes);
}

impl Record {
    pub fn new(kind: FaultKind, message: &[u8]) -> Record {
        Record {
            pid: 0,
            kind,
            message: message.to_vec(),
            frames: Vec::new(),
            truncated: false,
            cleanup_faults: Vec::new(),
            site: None,
        }
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(64 + self.message.len());
        out.extend_from_slice(MAGIC);
        out.push(VERSION);
        out.extend_from_slice(&self.pid.to_le_bytes());
        out.push(self.kind as u8);
        out.push(
            if self.truncated { TRUNCATED } else { 0 }
                | if self.site.is_some() { HAS_SITE } else { 0 },
        );
        put_bytes(&mut out, &self.message);
        out.extend_from_slice(&(self.frames.len() as u32).to_le_bytes());
        for f in &self.frames {
            put_bytes(&mut out, f.file.as_bytes());
            out.extend_from_slice(&f.line.to_le_bytes());
            put_bytes(&mut out, f.function.as_bytes());
            out.extend_from_slice(&f.repeated.to_le_bytes());
        }
        out.extend_from_slice(&(self.cleanup_faults.len() as u32).to_le_bytes());
        for c in &self.cleanup_faults {
            put_bytes(&mut out, c);
        }
        if let Some(site) = &self.site {
            put_bytes(&mut out, site);
        }
        out
    }

    /// `None` when `bytes` is not a record of this version.
    pub fn decode(bytes: &[u8]) -> Option<Record> {
        let mut r = Reader(bytes);
        if r.take(4)? != MAGIC || r.u8()? != VERSION {
            return None;
        }
        let pid = r.u32()?;
        let kind = FaultKind::from_code(r.u8()?);
        let flags = r.u8()?;
        let message = r.bytes()?.to_vec();
        let mut frames = Vec::new();
        for _ in 0..r.u32()? {
            let file = String::from_utf8_lossy(r.bytes()?).into_owned();
            let line = r.u32()?;
            let function = String::from_utf8_lossy(r.bytes()?).into_owned();
            let repeated = r.u32()?;
            frames.push(Frame {
                file,
                line,
                function,
                repeated,
            });
        }
        let mut cleanup_faults = Vec::new();
        for _ in 0..r.u32()? {
            cleanup_faults.push(r.bytes()?.to_vec());
        }
        let site = if flags & HAS_SITE != 0 {
            Some(r.bytes()?.to_vec())
        } else {
            None
        };
        Some(Record {
            pid,
            kind,
            message,
            frames,
            truncated: flags & TRUNCATED != 0,
            cleanup_faults,
            site,
        })
    }
}

struct Reader<'a>(&'a [u8]);

impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let (head, rest) = self.0.split_at_checked(n)?;
        self.0 = rest;
        Some(head)
    }
    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }
    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }
    fn bytes(&mut self) -> Option<&'a [u8]> {
        let n = self.u32()? as usize;
        self.take(n)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let mut r = Record::new(FaultKind::DivisionByZero, b"division by zero");
        r.frames.push(Frame {
            file: "/w/main.ms".into(),
            line: 7,
            function: "divide".into(),
            repeated: 3,
        });
        r.pid = 42;
        r.truncated = true;
        r.cleanup_faults.push(b"close failed\ndetail".to_vec());
        r.site = Some(b"/w/a:b.ms:3:9".to_vec());
        assert_eq!(Record::decode(&r.encode()), Some(r));
        assert_eq!(Record::decode(b"junk"), None);
    }
}
