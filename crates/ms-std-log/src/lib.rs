//! `@std/log.ms` natives: the record encoder and logger state.
//!
//! A [`Logger`] turns a level, message and optional JSON fields into the newline-terminated JSON
//! line a transport writes. Transports (streams, files, stdout), the clock and interface dispatch
//! belong to the generated code and the host runtime; they hand the current time in and write the
//! returned bytes out.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod ffi;

use alloc::string::{String, ToString};
use alloc::vec::Vec;
use core::sync::atomic::{AtomicUsize, Ordering};
use ms_rt::ffi::Fail;
use ms_std_json::{Doc, Limits, Node, NodeId};

/// Levels from Trace (0) to Silent (6); only 0 through 5 can label a record.
pub const SILENT: usize = 6;
const DEFAULT_LEVEL: usize = 2;

/// The `LogError` cases a native produces.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LogFail {
    InvalidInput,
    InvalidData,
    LimitExceeded,
}

impl LogFail {
    /// The status byte returned across the C ABI.
    pub fn status(self) -> u8 {
        match self {
            LogFail::InvalidInput => ms_rt_abi::STATUS_INVALID_INPUT,
            LogFail::InvalidData => ms_rt_abi::STATUS_INVALID_DATA,
            LogFail::LimitExceeded => ms_rt_abi::STATUS_LIMIT_EXCEEDED,
        }
    }
}

/// Returns stringified JSON as an object text: an object is unchanged, anything else is carried
/// under the key `data`.
pub fn object_text(text: &str) -> String {
    if text.starts_with('{') {
        text.to_string()
    } else {
        alloc::format!("{{\"data\":{text}}}")
    }
}

/// Reads fields text into an arena and the members of its top-level object.
fn parse_fields(text: &str) -> Result<(Doc, Vec<(String, NodeId)>), LogFail> {
    let (doc, root) =
        ms_std_json::parse(text, Limits::default()).map_err(|_| LogFail::InvalidData)?;
    match doc.nodes.get(root as usize) {
        Some(Node::Object(members)) => {
            let members = members.clone();
            Ok((doc, members))
        }
        _ => Err(LogFail::InvalidData),
    }
}

/// Copies `members` over `into`: later values override earlier ones without moving the key.
fn merge(into: &mut Vec<(String, NodeId)>, members: &[(String, NodeId)]) {
    for (k, v) in members {
        match into.iter_mut().find(|(ek, _)| ek == k) {
            Some(slot) => slot.1 = *v,
            None => into.push((k.clone(), *v)),
        }
    }
}

/// Appends `other`'s nodes to `doc`, returning the offset to add to its node ids.
fn absorb(doc: &mut Doc, other: Doc) -> NodeId {
    let base = doc.nodes.len() as NodeId;
    for node in other.nodes {
        doc.nodes.push(match node {
            Node::Array(ids) => Node::Array(ids.into_iter().map(|i| i + base).collect()),
            Node::Object(m) => Node::Object(m.into_iter().map(|(k, i)| (k, i + base)).collect()),
            n => n,
        });
    }
    base
}

pub struct Logger {
    threshold: AtomicUsize,
    doc: Doc,
    bindings: Vec<(String, NodeId)>,
    timestamp: bool,
    /// Largest line in bytes including the newline; `None` is unlimited.
    max: Option<usize>,
}

impl Logger {
    /// `Log_Create`: `level` is a level index; a negative `max_bytes` or a level above Silent is invalid.
    pub fn new(
        level: Option<usize>,
        timestamp: Option<bool>,
        max_bytes: Option<i64>,
    ) -> Result<Logger, LogFail> {
        let threshold = level.unwrap_or(DEFAULT_LEVEL);
        let max = match max_bytes {
            None => None,
            Some(n) => Some(usize::try_from(n).map_err(|_| LogFail::InvalidInput)?),
        };
        if threshold > SILENT {
            return Err(LogFail::InvalidInput);
        }
        Ok(Logger {
            threshold: AtomicUsize::new(threshold),
            doc: Doc::default(),
            bindings: Vec::new(),
            timestamp: timestamp.unwrap_or(true),
            max,
        })
    }

    pub fn level(&self) -> usize {
        self.threshold.load(Ordering::Relaxed)
    }

    pub fn set_level(&self, level: usize) {
        self.threshold.store(level, Ordering::Relaxed);
    }

    /// Whether a record at `level` would be written.
    pub fn enabled(&self, level: i64) -> bool {
        usize::try_from(level).is_ok_and(|l| l >= self.level() && l < SILENT)
    }

    /// `ChildJson`: a logger adding the members of the object text `fields` to each record.
    pub fn child(&self, fields: &str) -> Result<Logger, LogFail> {
        let (other, members) = parse_fields(fields)?;
        let mut doc = Doc {
            nodes: self.doc.nodes.clone(),
        };
        let base = absorb(&mut doc, other);
        let mut bindings = self.bindings.clone();
        let shifted: Vec<_> = members.into_iter().map(|(k, i)| (k, i + base)).collect();
        merge(&mut bindings, &shifted);
        Ok(Logger {
            threshold: AtomicUsize::new(self.level()),
            doc,
            bindings,
            timestamp: self.timestamp,
            max: self.max,
        })
    }

    /// `Log` and the level shorthands: the line to write, or `None` below the threshold.
    pub fn log(&self, level: i64, message: &str, now_ms: i64) -> Result<Option<Vec<u8>>, LogFail> {
        self.emit(level, message, None, now_ms)
    }

    /// `LogJson`: as [`Logger::log`] with the members of the object text `fields` added.
    pub fn log_json(
        &self,
        level: i64,
        message: &str,
        fields: &str,
        now_ms: i64,
    ) -> Result<Option<Vec<u8>>, LogFail> {
        if !(0..SILENT as i64).contains(&level) {
            return Err(LogFail::InvalidInput);
        }
        if !self.enabled(level) {
            return Ok(None);
        }
        let parsed = parse_fields(fields)?;
        self.emit(level, message, Some(parsed), now_ms)
    }

    fn emit(
        &self,
        level: i64,
        message: &str,
        fields: Option<(Doc, Vec<(String, NodeId)>)>,
        now_ms: i64,
    ) -> Result<Option<Vec<u8>>, LogFail> {
        if !(0..SILENT as i64).contains(&level) {
            return Err(LogFail::InvalidInput);
        }
        if (level as usize) < self.level() {
            return Ok(None);
        }
        let mut doc = Doc {
            nodes: self.doc.nodes.clone(),
        };
        let mut merged = self.bindings.clone();
        if let Some((other, members)) = fields {
            let base = absorb(&mut doc, other);
            let shifted: Vec<_> = members.into_iter().map(|(k, i)| (k, i + base)).collect();
            merge(&mut merged, &shifted);
        }
        let mut record = Vec::with_capacity(merged.len() + 3);
        record.push((
            "level".to_string(),
            doc.add(Node::Number(((level + 1) * 10).to_string())),
        ));
        record.push(("msg".to_string(), doc.add(Node::Str(message.to_string()))));
        if self.timestamp {
            record.push((
                "time".to_string(),
                doc.add(Node::Number(now_ms.to_string())),
            ));
        }
        // These keys belong to the record envelope even when time is disabled.
        record.extend(
            merged
                .into_iter()
                .filter(|(k, _)| !matches!(k.as_str(), "level" | "msg" | "time")),
        );
        let max = match self.max {
            Some(0) => return Err(LogFail::LimitExceeded),
            Some(n) => Some(i64::try_from(n - 1).unwrap_or(i64::MAX)),
            None => None,
        };
        let root = doc.add(Node::Object(record));
        let line = doc.stringify(root, max, None).map_err(|e| match e {
            Fail::LimitExceeded => LogFail::LimitExceeded,
            _ => LogFail::InvalidData,
        })?;
        let mut bytes = line.into_bytes();
        bytes.push(b'\n');
        Ok(Some(bytes))
    }
}
