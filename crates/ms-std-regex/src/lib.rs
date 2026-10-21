//! `@std/string.ms` natives, on top of the
//! `regex` crate; see [`translate`] for the dialect differences that are bridged.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod ffi;
mod translate;

use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::Fail;

/// A compiled pattern.
pub struct Regex(regex::Regex);

pub fn compile(pattern: &str) -> Result<Regex, Fail> {
    let translated = translate::translate(pattern).map_err(|()| Fail::InvalidData)?;
    regex::RegexBuilder::new(&translated)
        .size_limit(64 << 20)
        .build()
        .map(Regex)
        .map_err(|_| Fail::InvalidData)
}

impl Regex {
    pub fn is_match(&self, text: &str) -> bool {
        self.0.is_match(text)
    }

    /// Go's `FindAll` iteration: an empty match abutting the previous match is skipped.
    fn spans(&self, text: &str, limit: usize) -> Vec<(usize, usize)> {
        let mut found = Vec::new();
        let (mut pos, mut prev_end) = (0usize, usize::MAX);
        while found.len() < limit && pos <= text.len() {
            let Some(m) = self.0.find_at(text, pos) else {
                break;
            };
            let mut accept = true;
            if m.end() == pos {
                if m.start() == prev_end {
                    accept = false;
                }
                pos += text[pos..].chars().next().map_or(1, char::len_utf8);
            } else {
                pos = m.end();
            }
            prev_end = m.end();
            if accept {
                found.push((m.start(), m.end()));
            }
        }
        found
    }

    pub fn find_all(&self, text: &str, max: Option<i64>) -> Result<Vec<String>, Fail> {
        let max = limit(max)?;
        let n = max.min(text.len() + 1);
        let spans = self.spans(text, n + 1);
        if spans.len() > n {
            return Err(Fail::LimitExceeded);
        }
        Ok(spans.into_iter().map(|(a, b)| text[a..b].into()).collect())
    }

    pub fn replace_all(
        &self,
        text: &str,
        replacement: &str,
        max: Option<i64>,
    ) -> Result<String, Fail> {
        let max = limit(max)?;
        let mut out = String::new();
        let mut at = 0;
        for (a, b) in self.spans(text, usize::MAX) {
            if a - at > max - out.len() {
                return Err(Fail::LimitExceeded);
            }
            out.push_str(&text[at..a]);
            if replacement.len() > max - out.len() {
                return Err(Fail::LimitExceeded);
            }
            out.push_str(replacement);
            at = b;
        }
        if text.len() - at > max - out.len() {
            return Err(Fail::LimitExceeded);
        }
        out.push_str(&text[at..]);
        Ok(out)
    }
}

fn limit(max: Option<i64>) -> Result<usize, Fail> {
    match max {
        None => Ok(usize::MAX),
        Some(n) => usize::try_from(n).map_err(|_| Fail::InvalidInput),
    }
}
