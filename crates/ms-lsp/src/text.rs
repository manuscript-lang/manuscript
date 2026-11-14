//! Source text coordinates: UTF-16 LSP positions, offsets, and the forgiving
//! scanner used for cursor context.
//!
//! Source offsets are bytes of the original text. LSP columns count UTF-16
//! code units within a line.

use crate::json::{Json, obj};

/// A zero-based LSP position.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub struct Position {
    /// Line.
    pub line: usize,
    /// UTF-16 column.
    pub character: usize,
}

/// A half-open LSP range.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq)]
pub struct Range {
    /// Start.
    pub start: Position,
    /// End.
    pub end: Position,
}

impl Position {
    /// The JSON form.
    pub fn json(self) -> Json {
        obj([
            ("line", self.line.into()),
            ("character", self.character.into()),
        ])
    }

    /// Reads `{line, character}`.
    pub fn from_json(value: &Json) -> Option<Position> {
        Some(Position {
            line: usize::try_from(value.get("line")?.as_i64()?).ok()?,
            character: usize::try_from(value.get("character")?.as_i64()?).ok()?,
        })
    }
}

impl Range {
    /// The JSON form.
    pub fn json(self) -> Json {
        obj([("start", self.start.json()), ("end", self.end.json())])
    }

    /// Reads `{start, end}`.
    pub fn from_json(value: &Json) -> Option<Range> {
        Some(Range {
            start: Position::from_json(value.get("start")?)?,
            end: Position::from_json(value.get("end")?)?,
        })
    }

    /// An empty range at `p`.
    pub fn at(p: Position) -> Range {
        Range { start: p, end: p }
    }
}

/// UTF-16 length of UTF-8 bytes; each invalid byte counts as one unit, as a
/// rune error does when Go ranges over a string.
pub fn utf16_length(bytes: &[u8]) -> usize {
    let mut length = 0;
    for chunk in bytes.utf8_chunks() {
        length += chunk.valid().chars().map(char::len_utf16).sum::<usize>();
        length += chunk.invalid().len();
    }
    length
}

/// The LSP position of a byte offset (clamped into the source).
pub fn position(source: &str, offset: usize) -> Position {
    let bytes = source.as_bytes();
    let offset = offset.min(bytes.len());
    let prefix = &bytes[..offset];
    let line = prefix.iter().filter(|&&b| b == b'\n').count();
    let start = prefix
        .iter()
        .rposition(|&b| b == b'\n')
        .map_or(0, |at| at + 1);
    Position {
        line,
        character: utf16_length(&prefix[start..]),
    }
}

/// Line starts indexed once for a batch of conversions.
pub struct SourcePositions<'a> {
    source: &'a str,
    starts: Vec<usize>,
}

impl<'a> SourcePositions<'a> {
    /// Indexes `source`.
    pub fn new(source: &'a str) -> SourcePositions<'a> {
        let mut starts = vec![0];
        starts.extend(
            source
                .bytes()
                .enumerate()
                .filter(|&(_, b)| b == b'\n')
                .map(|(at, _)| at + 1),
        );
        SourcePositions { source, starts }
    }

    /// The position of a byte offset (clamped).
    pub fn position(&self, offset: usize) -> Position {
        let offset = offset.min(self.source.len());
        let line = self.starts.partition_point(|&s| s <= offset) - 1;
        Position {
            line,
            character: utf16_length(&self.source.as_bytes()[self.starts[line]..offset]),
        }
    }

    /// The range of two byte offsets.
    pub fn range(&self, start: usize, end: usize) -> Range {
        Range {
            start: self.position(start),
            end: self.position(end),
        }
    }
}

/// Coordinates for an ordered batch without rescanning already visited text.
pub(crate) struct ForwardPositions<'a> {
    source: &'a str,
    offset: usize,
    at: Position,
}

impl<'a> ForwardPositions<'a> {
    pub(crate) fn new(source: &'a str) -> Self {
        Self {
            source,
            offset: 0,
            at: Position::default(),
        }
    }

    pub(crate) fn position(&mut self, offset: usize) -> Position {
        let offset = offset.min(self.source.len());
        if offset < self.offset || !self.source.is_char_boundary(offset) {
            return position(self.source, offset);
        }
        let next = &self.source[self.offset..offset];
        if let Some(last) = next.rfind('\n') {
            self.at.line += next.bytes().filter(|&b| b == b'\n').count();
            self.at.character = utf16_length(&next.as_bytes()[last + 1..]);
        } else {
            self.at.character += utf16_length(next.as_bytes());
        }
        self.offset = offset;
        self.at
    }
}

/// Resolves an LSP position to a byte offset, rejecting positions that split a
/// surrogate pair or fall outside the document.
pub fn offset(source: &str, p: Position) -> Result<usize, &'static str> {
    resolve(source, p, false)
}

/// Resolves a change range the way the protocol asks servers to: a character
/// past the end of a line, or a line past the end of the document, clamps
/// instead of rejecting the edit.
pub fn edit_offset(source: &str, p: Position) -> Result<usize, &'static str> {
    resolve(source, p, true)
}

fn resolve(source: &str, p: Position, clamp: bool) -> Result<usize, &'static str> {
    let bytes = source.as_bytes();
    let mut at = 0;
    for _ in 0..p.line {
        match bytes[at..].iter().position(|&b| b == b'\n') {
            Some(next) => at += next + 1,
            None if clamp => return Ok(bytes.len()),
            None => return Err("line outside document"),
        }
    }
    let mut column = 0;
    while at < bytes.len() && bytes[at] != b'\n' && bytes[at] != b'\r' {
        if column == p.character {
            return Ok(at);
        }
        let (width, size) = rune_width(&bytes[at..]);
        column += width;
        at += size;
        if column > p.character {
            return Err("position splits a surrogate pair");
        }
    }
    if column != p.character && !clamp {
        return Err("character outside line");
    }
    Ok(at)
}

/// The UTF-16 width and byte size of the first rune of `bytes`; an invalid
/// byte is one unit and one byte.
fn rune_width(bytes: &[u8]) -> (usize, usize) {
    let size = match bytes[0] {
        0..=0x7f => 1,
        0xc0..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf7 => 4,
        _ => return (1, 1),
    };
    match bytes.get(..size).and_then(|b| std::str::from_utf8(b).ok()) {
        Some(text) => (text.chars().next().map_or(1, char::len_utf16), size),
        None => (1, 1),
    }
}

/// Whether `b` can be part of an identifier.
pub fn identifier(b: u8) -> bool {
    b == b'_' || b.is_ascii_alphanumeric()
}

/// What an editor token is.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum EditorKind {
    /// A `#` comment to the end of the line.
    Comment,
    /// A string literal, possibly unterminated.
    Str,
    /// An identifier, keyword or number.
    Name,
    /// An ASCII punctuation byte, or the leading byte of another Unicode scalar.
    Char(u8),
}

/// A token of the forgiving scanner.
#[derive(Copy, Clone, Debug)]
pub struct EditorToken<'a> {
    /// Kind.
    pub kind: EditorKind,
    /// The complete token's original text.
    pub text: &'a str,
    /// Start byte.
    pub start: usize,
    /// End byte (exclusive).
    pub end: usize,
}

impl EditorToken<'_> {
    /// Whether this is the punctuation byte `c`.
    pub fn is(&self, c: u8) -> bool {
        self.kind == EditorKind::Char(c)
    }

    /// Whether this is a name spelled `word`.
    pub fn is_name(&self, word: &str) -> bool {
        self.kind == EditorKind::Name && self.text == word
    }
}

/// The trimmed text of the last nonblank line before `line_start`.
pub fn previous_code_line(text: &str, line_start: usize) -> Option<&str> {
    text[..line_start]
        .lines()
        .rev()
        .map(str::trim)
        .find(|line| !line.is_empty())
}

/// Finds a checked declaration's name on the line after `offset` (skipping a
/// newline exactly at `offset`); the position of a header's declared name,
/// whatever precedes it.
pub fn header(source: &str, offset: usize, name: &str) -> Option<usize> {
    let tail = source.get(offset..)?;
    let newline = if tail.starts_with("\r\n") {
        2
    } else {
        usize::from(tail.starts_with('\n'))
    };
    let start = offset + newline;
    let line = source[start..].split('\n').next()?;
    editor_tokens(line)
        .into_iter()
        .find(|token| token.kind == EditorKind::Name && token.text == name)
        .map(|token| start + token.start)
}

/// A forgiving literal boundary in original source coordinates.
pub(crate) struct LiteralSpan {
    pub start: usize,
    pub end: usize,
    pub closed: bool,
    /// Delimiters for the private query snapshot, never edits to the document.
    pub closing: String,
    /// Mode transitions keep nested text/interpolation lookup on the same scan.
    contexts: Vec<(usize, Option<usize>)>,
}

impl LiteralSpan {
    pub(crate) fn interpolation_at(&self, offset: usize) -> Option<usize> {
        self.contexts
            .iter()
            .take_while(|(at, _)| *at <= offset)
            .last()
            .and_then(|(_, expression)| *expression)
    }
}

/// Closing state at a literal token's end, including a partial multiline closer.
pub(crate) fn literal_is_closed(source: &str) -> bool {
    literal_span(source.as_bytes(), 0).closed
}

/// Multiline-aware boundaries independent of whether the whole document lexes.
/// This scanner supplies editor context only, never compiler tokens/validation.
pub(crate) fn multiline_string_spans(source: &str) -> Option<Vec<LiteralSpan>> {
    if !source.contains("\"\"\"") {
        return None;
    }
    let bytes = source.as_bytes();
    let mut spans = Vec::new();
    let mut at = 0;
    while at < bytes.len() {
        if bytes[at..].starts_with(b"//") {
            at += source[at..].find('\n').unwrap_or(bytes.len() - at);
        } else if bytes[at..].starts_with(b"/*") {
            at += source[at + 2..]
                .find("*/")
                .map_or(bytes.len() - at, |n| n + 4);
        } else if bytes[at] == b'"' || bytes[at..].starts_with(b"r\"\"\"") {
            let span = literal_span(bytes, at);
            at = span.end;
            spans.push(span);
        } else if bytes[at..].starts_with(b"r\"") {
            // One-line raw text: no escapes, ends at the first quote or line.
            at += 2;
            while at < bytes.len() && !matches!(bytes[at], b'"' | b'\n') {
                at += 1;
            }
            at = (at + 1).min(bytes.len());
        } else if identifier(bytes[at]) {
            while at < bytes.len() && identifier(bytes[at]) {
                at += 1;
            }
        } else {
            at += 1;
        }
    }
    Some(spans)
}

fn literal_span(bytes: &[u8], start: usize) -> LiteralSpan {
    // An explicit stack keeps adversarial nesting off the native call stack.
    // This intentionally tolerates unfinished/invalid text; indentation, escape
    // validity and interpolation restrictions remain the compiler's decisions.
    enum Mode {
        Text { multiline: bool, raw: bool },
        Expression { groups: Vec<u8>, from: usize },
    }
    let raw = bytes[start] == b'r';
    let multiline = raw || bytes[start..].starts_with(b"\"\"\"");
    let mut modes = vec![Mode::Text { multiline, raw }];
    let mut contexts = vec![(start, None)];
    let mut at = start
        + if raw {
            4
        } else if multiline {
            3
        } else {
            1
        };
    while at < bytes.len() {
        let top_level = modes.len() == 1;
        match modes.last_mut().expect("literal mode") {
            Mode::Text { multiline, raw } => {
                if top_level && !*multiline && matches!(bytes[at], b'\n' | b'\r') {
                    // A broken single-line literal cannot consume a later
                    // declaration's multiline opener.
                    return LiteralSpan {
                        start,
                        end: at,
                        closed: false,
                        closing: "\"".into(),
                        contexts,
                    };
                } else if bytes[at] == b'\\' && !*raw {
                    if bytes[at..].starts_with(b"\\u{") {
                        at += 3;
                        while at < bytes.len() && bytes[at] != b'}' {
                            at += 1;
                        }
                        at = (at + 1).min(bytes.len());
                    } else {
                        at = (at + 2).min(bytes.len());
                    }
                } else if bytes[at] == b'"' && (!*multiline || bytes[at..].starts_with(b"\"\"\"")) {
                    at += if *multiline { 3 } else { 1 };
                    modes.pop();
                    if modes.is_empty() {
                        return LiteralSpan {
                            start,
                            end: at,
                            closed: true,
                            closing: String::new(),
                            contexts,
                        };
                    }
                } else if bytes[at] == b'{' && !*raw {
                    modes.push(Mode::Expression {
                        groups: Vec::new(),
                        from: at + 1,
                    });
                    at += 1;
                } else {
                    at += 1;
                }
            }
            Mode::Expression { groups, .. } => {
                if bytes[at..].starts_with(b"//") {
                    while at < bytes.len() && bytes[at] != b'\n' {
                        at += 1;
                    }
                } else if bytes[at..].starts_with(b"/*") {
                    at += 2;
                    while at < bytes.len() && !bytes[at..].starts_with(b"*/") {
                        at += 1;
                    }
                    at = (at + 2).min(bytes.len());
                } else if bytes[at] == b'"' {
                    modes.push(Mode::Text {
                        multiline: false,
                        raw: false,
                    });
                    at += 1;
                } else if matches!(bytes[at], b'{' | b'(' | b'[') {
                    groups.push(bytes[at]);
                    at += 1;
                } else if bytes[at] == b'}' {
                    if groups.is_empty() {
                        modes.pop();
                    } else {
                        groups.pop();
                    }
                    at += 1;
                } else if matches!(bytes[at], b')' | b']') {
                    groups.pop();
                    at += 1;
                } else {
                    at += 1;
                }
            }
        }
        let context = match modes.last() {
            Some(Mode::Expression { from, .. }) => Some(*from),
            _ => None,
        };
        if contexts
            .last()
            .is_none_or(|(_, previous)| *previous != context)
        {
            contexts.push((at, context));
        }
    }
    let mut closing = String::new();
    for mode in modes.iter().rev() {
        match mode {
            Mode::Text { multiline, .. } => {
                closing.push_str(if *multiline { "\n\"\"\"" } else { "\"" })
            }
            Mode::Expression { groups, .. } => {
                for group in groups.iter().rev() {
                    closing.push(match group {
                        b'(' => ')',
                        b'[' => ']',
                        _ => '}',
                    });
                }
                closing.push('}');
            }
        }
    }
    LiteralSpan {
        start,
        end: at,
        closed: false,
        closing,
        contexts,
    }
}

/// Scans tolerating unfinished strings and delimiters. It is only a cursor
/// context scanner; semantic types and visibility always come from the checker.
pub fn editor_tokens(source: &str) -> Vec<EditorToken<'_>> {
    let bytes = source.as_bytes();
    let strings = multiline_string_spans(source).unwrap_or_default();
    let mut strings = strings.into_iter().peekable();
    let mut result = Vec::new();
    let mut at = 0;
    while at < bytes.len() {
        let start = at;
        let b = bytes[at];
        if strings.peek().is_some_and(|span| span.start == at) {
            let end = strings.next().expect("peeked string").end;
            result.push(token(source, EditorKind::Str, at, end));
            at = end;
            continue;
        }
        if b == b' ' || b == b'\r' || b == b'\t' {
            at += 1;
            continue;
        }
        if b == b'/' && bytes.get(at + 1) == Some(&b'/') {
            while at < bytes.len() && bytes[at] != b'\n' {
                at += 1;
            }
            result.push(token(source, EditorKind::Comment, start, at));
            continue;
        }
        if b == b'/' && bytes.get(at + 1) == Some(&b'*') {
            // One token per line, so clients that do not take multi-line tokens still color it.
            let close = source[at + 2..]
                .find("*/")
                .map_or(bytes.len(), |c| at + 2 + c + 2);
            let mut line = at;
            while line < close {
                let end = source[line..close].find('\n').map_or(close, |n| line + n);
                if end > line {
                    result.push(token(source, EditorKind::Comment, line, end));
                }
                line = end + 1;
            }
            at = close;
            continue;
        }
        if b == b'"' {
            at += 1;
            while at < bytes.len() {
                if bytes[at] == b'\\' {
                    at += 1;
                    if at < bytes.len() {
                        at += 1;
                    }
                    continue;
                }
                if bytes[at] == b'"' {
                    at += 1;
                    break;
                }
                at += 1;
            }
            result.push(token(source, EditorKind::Str, start, at));
            continue;
        }
        if identifier(b) {
            while at < bytes.len() && identifier(bytes[at]) {
                at += 1;
            }
            result.push(token(source, EditorKind::Name, start, at));
            continue;
        }
        at += rune_width(&bytes[at..]).1;
        result.push(token(source, EditorKind::Char(b), start, at));
    }
    result
}

fn token(source: &str, kind: EditorKind, start: usize, end: usize) -> EditorToken<'_> {
    EditorToken {
        kind,
        text: source.get(start..end).unwrap_or(""),
        start,
        end,
    }
}

/// Where a diagnostic at `offset` inside `token` ends. A text literal is one token, but a
/// diagnostic inside its interpolation (`{name}`) covers only the name there, not the rest
/// of the literal.
fn diagnostic_end(source: &str, token: &EditorToken<'_>, offset: usize) -> usize {
    if token.kind != EditorKind::Str || offset == token.start {
        return token.end;
    }
    let rest = source.as_bytes().get(offset..token.end).unwrap_or_default();
    match rest.iter().take_while(|&&b| identifier(b)).count() {
        0 => token.end,
        name => offset + name,
    }
}

/// The range of the token containing `offset`, or an empty range at it.
pub fn diagnostic_range(source: &str, offset: usize) -> Range {
    let start = position(source, offset);
    let mut end = start;
    if let Some(t) = editor_tokens(source)
        .into_iter()
        .find(|t| offset >= t.start && offset < t.end)
    {
        end = position(source, diagnostic_end(source, &t, offset));
    }
    Range { start, end }
}

/// Token and line indexes shared by one document's diagnostic publication.
pub struct DiagnosticRanges<'a> {
    positions: SourcePositions<'a>,
    tokens: Vec<EditorToken<'a>>,
}

impl<'a> DiagnosticRanges<'a> {
    /// Indexes the original snapshot once, including malformed text.
    pub fn new(source: &'a str) -> Self {
        Self {
            positions: SourcePositions::new(source),
            tokens: editor_tokens(source),
        }
    }

    /// The containing token's range, or an empty range for whitespace/EOF.
    pub fn range(&self, offset: usize) -> Range {
        let start = self.positions.position(offset);
        let index = self.tokens.partition_point(|token| token.end <= offset);
        let end = self
            .tokens
            .get(index)
            .filter(|token| token.start <= offset && offset < token.end)
            .map_or(start, |token| {
                self.positions
                    .position(diagnostic_end(self.positions.source, token, offset))
            });
        Range { start, end }
    }
}

/// The byte range of 0-based `line`, including its newline.
pub fn line_span(source: &str, line: usize) -> (usize, usize) {
    let bytes = source.as_bytes();
    let mut start = 0;
    for _ in 0..line {
        match bytes[start..].iter().position(|&b| b == b'\n') {
            Some(offset) => start += offset + 1,
            None => break,
        }
    }
    let end = match bytes[start..].iter().position(|&b| b == b'\n') {
        Some(offset) => start + offset + 1,
        None => bytes.len(),
    };
    (start, end)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn forward_positions_preserve_every_original_byte_position() {
        for source in ["", "plain", "a😀b\r\né\n\nlast\rignored", "\n😀\n日本\r\n"] {
            let mut positions = ForwardPositions::new(source);
            for offset in (0..=source.len() + 2)
                .chain((0..=source.len()).rev())
                .chain([0, 1, 2, source.len(), usize::MAX, 0, source.len()])
            {
                assert_eq!(positions.position(offset), position(source, offset));
            }
            let mut positions = ForwardPositions::new(source);
            for at in 0..=source.len() {
                for offset in [at, source.len() - at, at, at + 1] {
                    assert_eq!(positions.position(offset), position(source, offset));
                }
            }
            let mut positions = ForwardPositions::new(source);
            for offset in [0, 1, 2, 5, 0, 6, 5, 7, 3, source.len(), usize::MAX] {
                assert_eq!(positions.position(offset), position(source, offset));
            }
        }
    }

    #[test]
    fn a_diagnostic_in_an_interpolation_covers_the_name_not_the_rest_of_the_literal() {
        let source = "print(\"😀 {missing.x} tail\")\nprint(\"whole\")";
        let at = source.find("missing").unwrap();
        let range = diagnostic_range(source, at);
        assert_eq!(range.end.character - range.start.character, 7);
        let index = DiagnosticRanges::new(source).range(at);
        assert_eq!(index.end, range.end);
        let literal = DiagnosticRanges::new(source).range(source.find("\"whole").unwrap());
        assert_eq!(literal.end.character - literal.start.character, 7);
    }

    #[test]
    fn diagnostic_index_preserves_all_original_byte_ranges() {
        for source in [
            "",
            "a",
            "\n\r\n",
            "\t日本😀e\u{301} + wrong\r\n# note\r\n",
            "x := \"unfinished\n",
            "x := [\n1,\n",
            "a # comment\nnext",
        ] {
            let index = DiagnosticRanges::new(source);
            for offset in (0..=source.len() + 2).rev().chain([usize::MAX]) {
                assert_eq!(
                    index.range(offset),
                    diagnostic_range(source, offset),
                    "{source:?} at {offset}"
                );
            }
        }
    }

    #[test]
    fn many_diagnostics_reuse_the_document_indexes() {
        let source = "value := )\r\n".repeat(8000);
        let index = DiagnosticRanges::new(&source);
        let tokens = index.tokens.as_ptr();
        for line in (0..8000).rev() {
            let offset = line * 12 + 9;
            assert_eq!(
                index.range(offset),
                Range {
                    start: Position { line, character: 9 },
                    end: Position {
                        line,
                        character: 10
                    },
                }
            );
        }
        assert_eq!(index.tokens.as_ptr(), tokens);
        assert_eq!(index.positions.starts.len(), 8001);
    }

    #[test]
    fn utf16_columns() {
        let s = "// 😀é\r\nfn";
        assert_eq!(
            position(s, "// 😀é".len()),
            Position {
                line: 0,
                character: 6
            }
        );
        assert_eq!(
            position(s, s.len()),
            Position {
                line: 1,
                character: 2
            }
        );
        assert_eq!(SourcePositions::new(s).position(s.len()).character, 2);
    }

    #[test]
    fn offsets_reject_surrogate_splits() {
        let s = "a😀b\n";
        let at = |line, character| offset(s, Position { line, character });
        assert_eq!(at(0, 1), Ok(1));
        assert!(at(0, 2).is_err());
        assert_eq!(at(0, 3), Ok(5));
        assert!(at(1, 1).is_err());
        assert_eq!(
            edit_offset(
                s,
                Position {
                    line: 9,
                    character: 0
                }
            ),
            Ok(s.len())
        );
    }

    #[test]
    fn scanner_survives_unfinished_strings() {
        let tokens = editor_tokens("x := \"abc\n// note");
        // An unterminated string runs to the end of the source, as in the Go scanner.
        assert_eq!(tokens.len(), 4);
        assert_eq!(tokens[3].kind, EditorKind::Str);
        assert_eq!(tokens[3].end, "x := \"abc\n// note".len());
    }
}
