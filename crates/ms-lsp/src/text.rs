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

/// The position just past the last byte.
pub fn end_position(source: &str) -> Position {
    position(source, source.len())
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
    /// One other byte.
    Char(u8),
}

/// A token of the forgiving scanner.
#[derive(Copy, Clone, Debug)]
pub struct EditorToken<'a> {
    /// Kind.
    pub kind: EditorKind,
    /// Text (empty for a non-ASCII byte).
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

/// Scans tolerating unfinished strings and delimiters. It is only a cursor
/// context scanner; semantic types and visibility always come from the checker.
pub fn editor_tokens(source: &str) -> Vec<EditorToken<'_>> {
    let bytes = source.as_bytes();
    let mut result = Vec::new();
    let mut at = 0;
    while at < bytes.len() {
        let start = at;
        let b = bytes[at];
        if b == b' ' || b == b'\r' || b == b'\t' {
            at += 1;
            continue;
        }
        if b == b'#' {
            while at < bytes.len() && bytes[at] != b'\n' {
                at += 1;
            }
            result.push(token(source, EditorKind::Comment, start, at));
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
        at += 1;
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

/// The range of the token containing `offset`, or an empty range at it.
pub fn diagnostic_range(source: &str, offset: usize) -> Range {
    let start = position(source, offset);
    let mut end = start;
    if let Some(t) = editor_tokens(source)
        .into_iter()
        .find(|t| offset >= t.start && offset < t.end)
    {
        end = position(source, t.end);
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
            .map_or(start, |token| self.positions.position(token.end));
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
    fn diagnostic_index_preserves_all_original_byte_ranges() {
        for source in [
            "",
            "a",
            "\n\r\n",
            "\t日本😀e\u{301} + wrong\r\n# note\r\n",
            "let x = \"unfinished\n",
            "let x = [\n1,\n",
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
        let source = "let value = )\r\n".repeat(8000);
        let index = DiagnosticRanges::new(&source);
        let tokens = index.tokens.as_ptr();
        for line in (0..8000).rev() {
            let offset = line * 15 + 12;
            assert_eq!(
                index.range(offset),
                Range {
                    start: Position {
                        line,
                        character: 12
                    },
                    end: Position {
                        line,
                        character: 13
                    },
                }
            );
        }
        assert_eq!(index.tokens.as_ptr(), tokens);
        assert_eq!(index.positions.starts.len(), 8001);
    }

    #[test]
    fn utf16_columns() {
        let s = "# 😀é\r\nfn";
        assert_eq!(
            position(s, "# 😀é".len()),
            Position {
                line: 0,
                character: 5
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
        let tokens = editor_tokens("let x = \"abc\n# note");
        // An unterminated string runs to the end of the source, as in the Go scanner.
        assert_eq!(tokens.len(), 4);
        assert_eq!(tokens[3].kind, EditorKind::Str);
        assert_eq!(tokens[3].end, "let x = \"abc\n# note".len());
    }
}
