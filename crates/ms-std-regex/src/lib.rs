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
use ms_rt::ffi::Fail;

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

    /// Capture texts of the first match: the whole match, then each group (`""` when a group did
    /// not participate). Empty when nothing matches.
    pub fn captures(&self, text: &str) -> Vec<String> {
        self.0
            .captures(text)
            .map(|c| {
                c.iter()
                    .map(|g| g.map_or("", |m| m.as_str()).into())
                    .collect()
            })
            .unwrap_or_default()
    }

    /// [`captures`](Self::captures) for every match, under the `find_all` match budget.
    pub fn captures_all(&self, text: &str, max: Option<i64>) -> Result<Vec<Vec<String>>, Fail> {
        let max = limit(max)?;
        let n = max.min(text.len() + 1);
        let spans = self.spans(text, n + 1);
        if spans.len() > n {
            return Err(Fail::LimitExceeded);
        }
        Ok(spans
            .into_iter()
            .filter_map(|(a, b)| self.captures_at(text, a, b))
            .collect())
    }

    /// Captures of the match spanning exactly `a..b`, found by re-matching from `a`.
    fn captures_at(&self, text: &str, a: usize, b: usize) -> Option<Vec<String>> {
        let c = self.0.captures_at(text, a)?;
        let whole = c.get(0)?;
        debug_assert_eq!((whole.start(), whole.end()), (a, b));
        Some(
            c.iter()
                .map(|g| g.map_or("", |m| m.as_str()).into())
                .collect(),
        )
    }

    /// Named groups of the first match that participated; empty when nothing matches.
    pub fn named_captures(&self, text: &str) -> Vec<(Vec<u8>, Vec<u8>)> {
        let Some(c) = self.0.captures(text) else {
            return Vec::new();
        };
        self.0
            .capture_names()
            .flatten()
            .filter_map(|n| {
                c.name(n)
                    .map(|m| (n.as_bytes().to_vec(), m.as_str().as_bytes().to_vec()))
            })
            .collect()
    }

    /// `[start, end]` byte offsets of the first match; `None` when nothing matches.
    pub fn find_span(&self, text: &str) -> Option<[i64; 2]> {
        self.0
            .find(text)
            .map(|m| [m.start() as i64, m.end() as i64])
    }

    /// Pieces between matches; a supplied cap bounds the piece count like `find_all`.
    pub fn split(&self, text: &str, max: Option<i64>) -> Result<Vec<String>, Fail> {
        let max = limit(max)?;
        let spans = self.spans(text, usize::MAX);
        if spans.len() >= max {
            return Err(Fail::LimitExceeded);
        }
        let mut out = Vec::with_capacity(spans.len() + 1);
        let mut at = 0;
        for (a, b) in spans {
            out.push(text[at..a].into());
            at = b;
        }
        out.push(text[at..].into());
        Ok(out)
    }

    /// `replace_all` where `$1`, `${name}` and `$$` in the template expand per match.
    pub fn replace_template(
        &self,
        text: &str,
        template: &str,
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
            let Some(c) = self.0.captures_at(text, a) else {
                continue;
            };
            let mut piece = String::new();
            c.expand(template, &mut piece);
            if piece.len() > max - out.len() {
                return Err(Fail::LimitExceeded);
            }
            out.push_str(&piece);
            at = b;
        }
        if text.len() - at > max - out.len() {
            return Err(Fail::LimitExceeded);
        }
        out.push_str(&text[at..]);
        Ok(out)
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
