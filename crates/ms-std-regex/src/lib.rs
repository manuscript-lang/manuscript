//! `@std/string.ms` natives, on top of the `regex` crate and its pattern dialect.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod ffi;

use alloc::string::String;
use alloc::vec::Vec;
use ms_rt::ffi::Fail;

/// A compiled pattern.
pub struct Regex {
    pattern: regex::Regex,
    has_named_groups: bool,
    #[cfg(test)]
    scans: core::cell::Cell<usize>,
}

/// Match positions with Go's empty-match adjacency rule.
struct Spans<'a> {
    regex: &'a Regex,
    text: &'a str,
    pos: usize,
    prev_end: usize,
}

impl Iterator for Spans<'_> {
    type Item = (usize, usize);

    fn next(&mut self) -> Option<Self::Item> {
        while self.pos <= self.text.len() {
            #[cfg(test)]
            self.regex.scans.set(self.regex.scans.get() + 1);
            let m = self.regex.pattern.find_at(self.text, self.pos)?;
            let mut accept = true;
            if m.end() == self.pos {
                if m.start() == self.prev_end {
                    accept = false;
                }
                self.pos += self.text[self.pos..]
                    .chars()
                    .next()
                    .map_or(1, char::len_utf8);
            } else {
                self.pos = m.end();
            }
            self.prev_end = m.end();
            if accept {
                return Some((m.start(), m.end()));
            }
        }
        None
    }
}

pub fn compile(pattern: &str) -> Result<Regex, Fail> {
    let pattern = regex::RegexBuilder::new(pattern)
        .size_limit(64 << 20)
        .build()
        .map_err(|_| Fail::InvalidData)?;
    let has_named_groups = pattern.capture_names().any(|name| name.is_some());
    Ok(Regex {
        pattern,
        has_named_groups,
        #[cfg(test)]
        scans: core::cell::Cell::new(0),
    })
}

impl Regex {
    pub fn is_match(&self, text: &str) -> bool {
        self.pattern.is_match(text)
    }

    fn spans_iter<'a>(&'a self, text: &'a str) -> Spans<'a> {
        Spans {
            regex: self,
            text,
            pos: 0,
            prev_end: usize::MAX,
        }
    }

    fn spans(&self, text: &str, limit: usize) -> Vec<(usize, usize)> {
        let mut found = Vec::new();
        let (mut pos, mut prev_end) = (0usize, usize::MAX);
        while found.len() < limit && pos <= text.len() {
            #[cfg(test)]
            self.scans.set(self.scans.get() + 1);
            let Some(m) = self.pattern.find_at(text, pos) else {
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
        if self.pattern.captures_len() == 1 {
            return self
                .pattern
                .find(text)
                .map(|m| alloc::vec![m.as_str().into()])
                .unwrap_or_default();
        }
        self.pattern
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
        if spans.is_empty() {
            return Ok(Vec::new());
        }
        if self.pattern.captures_len() == 1 {
            return Ok(spans
                .into_iter()
                .map(|(a, b)| alloc::vec![text[a..b].into()])
                .collect());
        }
        let mut locations = self.pattern.capture_locations();
        Ok(spans
            .into_iter()
            .filter_map(|(a, b)| self.captures_at(&mut locations, text, a, b))
            .collect())
    }

    /// Captures of the match spanning exactly `a..b`, found by re-matching from `a`.
    fn captures_at(
        &self,
        locations: &mut regex::CaptureLocations,
        text: &str,
        a: usize,
        b: usize,
    ) -> Option<Vec<String>> {
        let whole = self.pattern.captures_read_at(locations, text, a)?;
        debug_assert_eq!((whole.start(), whole.end()), (a, b));
        Some(
            (0..locations.len())
                .map(|group| locations.get(group).map_or("", |(a, b)| &text[a..b]).into())
                .collect(),
        )
    }

    /// Named groups of the first match that participated; empty when nothing matches.
    pub fn named_captures(&self, text: &str) -> Vec<(Vec<u8>, Vec<u8>)> {
        if !self.has_named_groups {
            return Vec::new();
        }
        let Some(c) = self.pattern.captures(text) else {
            return Vec::new();
        };
        self.pattern
            .capture_names()
            .enumerate()
            .filter_map(|(index, name)| {
                let name = name?;
                c.get(index)
                    .map(|m| (name.as_bytes().to_vec(), m.as_str().as_bytes().to_vec()))
            })
            .collect()
    }

    /// `[start, end]` byte offsets of the first match; `None` when nothing matches.
    pub fn find_span(&self, text: &str) -> Option<[i64; 2]> {
        self.pattern
            .find(text)
            .map(|m| [m.start() as i64, m.end() as i64])
    }

    /// Pieces between matches; a supplied cap bounds the piece count like `find_all`.
    pub fn split(&self, text: &str, max: Option<i64>) -> Result<Vec<String>, Fail> {
        let max = limit(max)?;
        if max == usize::MAX {
            let spans = self.spans(text, usize::MAX);
            let mut out = Vec::with_capacity(spans.len() + 1);
            let mut at = 0;
            for (a, b) in spans {
                out.push(text[at..a].into());
                at = b;
            }
            out.push(text[at..].into());
            return Ok(out);
        }
        if max == 0 {
            return Err(Fail::LimitExceeded);
        }
        let mut out = Vec::new();
        let mut at = 0;
        for (a, b) in self.spans_iter(text) {
            if out.len() + 1 >= max {
                return Err(Fail::LimitExceeded);
            }
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
        let mut needs_expansion = None;
        let mut at = 0;
        for (a, b) in self.spans_iter(text) {
            if a - at > max - out.len() {
                return Err(Fail::LimitExceeded);
            }
            out.push_str(&text[at..a]);
            if *needs_expansion.get_or_insert_with(|| template.contains('$')) {
                let Some(c) = self.pattern.captures_at(text, a) else {
                    continue;
                };
                c.expand(template, &mut out);
            } else {
                if template.len() > max - out.len() {
                    return Err(Fail::LimitExceeded);
                }
                out.push_str(template);
            }
            if out.len() > max {
                return Err(Fail::LimitExceeded);
            }
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
        for (a, b) in self.spans_iter(text) {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_escapes_reject_non_hexadecimal_characters() {
        for pattern in [r"\x+1", r"\x{+41}", r"[\x+1]", r"[\x{+41}]"] {
            assert!(
                matches!(compile(pattern), Err(Fail::InvalidData)),
                "accepted invalid hexadecimal escape: {pattern}"
            );
        }
        for pattern in [r"\x41", r"\x{41}", r"[\x41]", r"[\x{41}]"] {
            assert!(compile(pattern).unwrap().is_match("A"));
        }
    }

    #[test]
    fn strict_limits_stop_scanning_when_failure_is_known() {
        let re = compile("x").unwrap();
        let text = "x".repeat(10_000);

        assert_eq!(re.split(&text, Some(0)), Err(Fail::LimitExceeded));
        assert_eq!(re.scans.get(), 0);
        assert_eq!(re.split(&text, Some(1)), Err(Fail::LimitExceeded));
        assert_eq!(re.scans.get(), 1);
        assert_eq!(
            re.replace_all(&text, "y", Some(0)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(re.scans.get(), 2);
        assert_eq!(
            re.replace_template(&text, "y", Some(0)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(re.scans.get(), 3);
    }

    #[test]
    fn split_preserves_pieces_and_limits() {
        let re = compile(",").unwrap();
        let pieces = alloc::vec!["a".into(), "b".into(), "c".into()];
        assert_eq!(re.split("a,b,c", None), Ok(pieces.clone()));
        assert_eq!(re.split("a,b,c", Some(3)), Ok(pieces));
        assert_eq!(re.split("a,b,c", Some(2)), Err(Fail::LimitExceeded));
        assert_eq!(re.split("a,b,c", Some(-1)), Err(Fail::InvalidInput));
        assert_eq!(re.split("abc", Some(1)), Ok(alloc::vec!["abc".into()]));
        assert_eq!(re.split("abc", Some(0)), Err(Fail::LimitExceeded));

        let empty = compile("").unwrap();
        assert_eq!(
            empty.split("é🙂", None),
            Ok(alloc::vec!["".into(), "é".into(), "🙂".into(), "".into()])
        );
        assert_eq!(
            empty.split("é🙂", Some(4)),
            Ok(alloc::vec!["".into(), "é".into(), "🙂".into(), "".into()])
        );
        assert_eq!(empty.split("é🙂", Some(3)), Err(Fail::LimitExceeded));
        let adjacent = compile("a*").unwrap();
        assert_eq!(
            adjacent.split("a🙂a", None),
            Ok(alloc::vec!["".into(), "🙂".into(), "".into()])
        );
    }

    #[test]
    fn incremental_spans_match_the_bounded_collector() {
        for pattern in ["", "a*", "a", "é|🙂"] {
            let re = compile(pattern).unwrap();
            for text in ["", "a🙂a", "é🙂é", "\na\n"] {
                assert_eq!(
                    re.spans_iter(text).collect::<Vec<_>>(),
                    re.spans(text, usize::MAX),
                    "pattern {pattern:?}, text {text:?}"
                );
            }
        }
    }

    #[test]
    fn captures_all_preserves_absent_groups_and_match_budgets() {
        let re = compile("(a)|(b+)").unwrap();
        let expected = alloc::vec![
            alloc::vec!["a".into(), "a".into(), "".into()],
            alloc::vec!["bbb".into(), "".into(), "bbb".into()],
            alloc::vec!["a".into(), "a".into(), "".into()],
        ];
        assert_eq!(re.captures_all("a bbb a", None), Ok(expected.clone()));
        assert_eq!(re.captures_all("a bbb a", Some(3)), Ok(expected));
        assert_eq!(
            re.captures_all("a bbb a", Some(2)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(re.captures_all("a", Some(0)), Err(Fail::LimitExceeded));
        assert_eq!(re.captures_all("", Some(0)), Ok(Vec::new()));
        assert_eq!(re.captures_all("a", Some(-1)), Err(Fail::InvalidInput));

        for pattern in ["", "a*", "(a)?", "(é)|(🙂)", "\\b(a)\\b"] {
            let re = compile(pattern).unwrap();
            for text in ["", "a🙂a", "é🙂é", "ba a"] {
                let expected: Vec<Vec<String>> = re
                    .spans_iter(text)
                    .map(|(a, _)| {
                        re.pattern
                            .captures_at(text, a)
                            .unwrap()
                            .iter()
                            .map(|group| group.map_or("", |m| m.as_str()).into())
                            .collect()
                    })
                    .collect();
                assert_eq!(
                    re.captures_all(text, None),
                    Ok(expected),
                    "{pattern:?} {text:?}"
                );
            }
        }
    }

    #[test]
    fn captures_without_explicit_groups_preserve_rows_context_and_limits() {
        for pattern in ["", "a*", "a+", "(?:a|b)+", "\\bword\\b", "^a", "a$"] {
            let re = compile(pattern).unwrap();
            for text in ["", "xyz", "a🙂🙂a", "baba", "sword word", "a\na"] {
                let first: Vec<String> = re
                    .pattern
                    .captures(text)
                    .map(|c| c.iter().map(|g| g.unwrap().as_str().into()).collect())
                    .unwrap_or_default();
                assert_eq!(re.captures(text), first, "{pattern:?} {text:?}");
                assert!(re.named_captures(text).is_empty());
                let rows: Vec<Vec<String>> = re
                    .spans_iter(text)
                    .map(|(a, b)| alloc::vec![text[a..b].into()])
                    .collect();
                let count = rows.len() as i64;
                assert_eq!(re.captures_all(text, None), Ok(rows.clone()));
                assert_eq!(re.captures_all(text, Some(count)), Ok(rows));
                if count > 0 {
                    assert_eq!(
                        re.captures_all(text, Some(count - 1)),
                        Err(Fail::LimitExceeded)
                    );
                }
                assert_eq!(re.captures_all(text, Some(-1)), Err(Fail::InvalidInput));
            }
        }

        // A nonparticipating optional group still owns a column.
        let re = compile("(a)?b").unwrap();
        let first: Vec<String> = alloc::vec!["b".into(), "".into()];
        assert_eq!(re.captures("b"), first);
        assert_eq!(
            re.captures_all("b b", None),
            Ok(alloc::vec![
                alloc::vec!["b".into(), "".into()],
                alloc::vec!["b".into(), "".into()]
            ])
        );
    }

    #[test]
    fn template_expands_repeated_matches_with_strict_byte_limits() {
        let re = compile("(?P<a>a+)|(b+)").unwrap();
        assert_eq!(
            re.replace_template("aaaaaaaa b a", "${a}:${2}$$", None),
            Ok("aaaaaaaa:$ :b$ a:$".into())
        );
        assert_eq!(
            re.replace_template("a b", "${1}x:$1x:$missing", None),
            Ok("ax:: x::".into())
        );
        assert_eq!(re.replace_template("a b", "", None), Ok(" ".into()));
        assert_eq!(
            re.replace_template("a b", "xy", Some(5)),
            Ok("xy xy".into())
        );
        assert_eq!(
            re.replace_template("a b", "xy", Some(4)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(re.replace_template("a b", "$$", Some(3)), Ok("$ $".into()));
        assert_eq!(
            re.replace_template("a b", "$$", Some(2)),
            Err(Fail::LimitExceeded)
        );
    }

    #[test]
    fn named_captures_preserve_indices_absence_and_empty_groups() {
        let re = compile("(a)?(?P<first>b)?(c)(?P<empty>d*)(?P<last>e)").unwrap();
        assert_eq!(
            re.named_captures("ce"),
            alloc::vec![
                (b"empty".to_vec(), Vec::new()),
                (b"last".to_vec(), b"e".to_vec())
            ]
        );
        assert_eq!(
            re.named_captures("abcde"),
            alloc::vec![
                (b"first".to_vec(), b"b".to_vec()),
                (b"empty".to_vec(), b"d".to_vec()),
                (b"last".to_vec(), b"e".to_vec()),
            ]
        );
        assert!(re.named_captures("xyz").is_empty());
    }

    #[test]
    fn named_captures_handles_patterns_without_names_and_late_names() {
        for pattern in ["", "word", "(word)([0-9]+)", "(a)?b"] {
            let re = compile(pattern).unwrap();
            for text in ["", "word123", "b", "xyz"] {
                assert!(re.named_captures(text).is_empty());
            }
        }
        let pattern = alloc::format!("{}(?P<last>x)", "(a?)".repeat(128));
        let re = compile(&pattern).unwrap();
        assert!(re.named_captures("z").is_empty());
        assert_eq!(
            re.named_captures("x"),
            alloc::vec![(b"last".to_vec(), b"x".to_vec())]
        );
    }

    #[test]
    fn replacements_preserve_literal_template_and_byte_limits() {
        let re = compile("(?P<name>é)").unwrap();
        assert_eq!(re.replace_all("aéb", "$1", None), Ok("a$1b".into()));
        assert_eq!(re.replace_all("aéb", "🙂", Some(6)), Ok("a🙂b".into()));
        assert_eq!(
            re.replace_all("aéb", "🙂", Some(5)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(
            re.replace_all("aéb", "🙂", Some(-1)),
            Err(Fail::InvalidInput)
        );
        assert_eq!(
            re.replace_template("aéb", "${name}$$", Some(5)),
            Ok("aé$b".into())
        );
        assert_eq!(
            re.replace_template("aéb", "${name}$$", Some(4)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(
            re.replace_template("aéb", "${name}$$", Some(-1)),
            Err(Fail::InvalidInput)
        );
        assert_eq!(re.replace_all("", "🙂", Some(0)), Ok("".into()));
        assert_eq!(re.replace_template("", "🙂", Some(0)), Ok("".into()));
        assert_eq!(re.replace_all("é", "🙂", Some(1)), Err(Fail::LimitExceeded));

        let empty = compile("").unwrap();
        assert_eq!(empty.replace_all("é🙂", "x", Some(9)), Ok("xéx🙂x".into()));
        assert_eq!(
            empty.replace_template("é🙂", "x", Some(9)),
            Ok("xéx🙂x".into())
        );
        assert_eq!(
            empty.replace_template("é🙂", "x", Some(8)),
            Err(Fail::LimitExceeded)
        );
    }
}
