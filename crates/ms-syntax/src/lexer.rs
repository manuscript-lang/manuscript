//! Lexer with layout: scans UTF-8 source and enforces the indentation rules,
//! emitting `Newline`/`Indent`/`Dedent` tokens.

use crate::diag::{Diagnostic, DiagnosticFix};
use crate::pos::Pos;
use crate::token::{Tok, Token};
use std::borrow::Cow;
use std::sync::Arc;

/// Result alias used by the lexer and parser; errors are boxed to keep `Result` small.
pub type PResult<T> = Result<T, Box<Diagnostic>>;

/// Lexer output.
pub struct Lexed<'a> {
    /// Source with CRLF replaced by LF; token text indexes into this.
    pub source: Cow<'a, str>,
    /// Tokens, ending with `Eof`.
    pub tokens: Vec<Token>,
    pub(crate) boundaries: ScanBoundaries,
}

/// Offsets in the normalized source, discovered while validating text once.
#[derive(Default)]
pub(crate) struct ScanBoundaries {
    strings: Vec<(usize, usize)>,
    interpolations: Vec<(usize, usize)>,
}

impl ScanBoundaries {
    fn string_end(&self, start: usize) -> Option<usize> {
        self.strings
            .binary_search_by_key(&start, |&(at, _)| at)
            .ok()
            .map(|i| self.strings[i].1)
    }

    pub(crate) fn interpolation_end(&self, start: usize) -> Option<usize> {
        self.interpolations
            .binary_search_by_key(&start, |&(at, _)| at)
            .ok()
            .map(|i| self.interpolations[i].1)
    }
}

fn letter(b: u8) -> bool {
    b.is_ascii_alphabetic() || b == b'_'
}
fn digit(b: u8) -> bool {
    b.is_ascii_digit()
}

struct Layout {
    indent: usize,
    depth: usize,
}

struct Scanner<'a> {
    file: &'a Arc<str>,
    src: &'a [u8],
    text: &'a str,
    offset: usize,
    line: u32,
    base_line: u32,
    base_offset: u32,
    column: u32,
    tokens: Vec<Token>,
    levels: Vec<Layout>,
    delimiters: Vec<u8>,
    groups: Vec<usize>,
    opened: Vec<Pos>,
    function_depths: Vec<usize>,
    /// CR bytes removed before each normalised line; empty when source had no CRLF.
    line_offsets: Vec<u32>,
    interpolations: Vec<Pos>,
    boundaries: ScanBoundaries,
    cached: Option<&'a ScanBoundaries>,
    boundary_origin: usize,
    virtual_paren: bool,
}

const BIDI_COMMENT: &str = "bidirectional text controls (U+202A..U+202E, U+2066..U+2069) are not allowed in comments because they can make source display differently from how it is read; remove the character";
const BIDI_TEXT: &str = "bidirectional text controls (U+202A..U+202E, U+2066..U+2069) are not allowed in text because they can make source display differently from how it is read; write the escape instead, e.g. \\u{202E}";
const BRACE_HINT: &str = "'{' starts an interpolation; write \\{ and \\} for literal braces";
const MAX_INTERPOLATION_DEPTH: usize = 1000;

/// Lexes `source`. `source` must be valid UTF-8 (use [`lex_bytes`] otherwise).
pub fn lex<'a>(file: &'a Arc<str>, source: &'a str) -> PResult<Lexed<'a>> {
    lex_at(file, source, 0, 0)
}

/// Lexes a slice of a larger file: its first byte is at original offset
/// `base_offset` and it starts on line `base_line + 1`.
pub(crate) fn lex_at<'a>(
    file: &'a Arc<str>,
    source: &'a str,
    base_offset: u32,
    base_line: u32,
) -> PResult<Lexed<'a>> {
    if source.starts_with('\u{feff}') {
        return Err(Box::new(Diagnostic::parse(
            file,
            Pos::new(base_offset, base_line + 1, 1),
            "a byte-order mark is not allowed; save the file as UTF-8 without BOM",
        )));
    }
    let (normalized, offsets) = normalize_source(source);
    let (tokens, mut boundaries) = {
        let mut s = Scanner::new(file, &normalized, base_offset, base_line, offsets);
        s.tokens.reserve(source.len() / 4 + 16);
        s.run(None)?;
        (s.tokens, s.boundaries)
    };
    boundaries.strings.sort_unstable_by_key(|&(start, _)| start);
    boundaries
        .interpolations
        .sort_unstable_by_key(|&(start, _)| start);
    Ok(Lexed {
        source: normalized,
        tokens,
        boundaries,
    })
}

/// Lex one already validated interpolation in its original source slice. A
/// virtual parenthesis gives it the same layout rules as the old wrapper.
pub(crate) fn lex_interpolation(
    file: &Arc<str>,
    source: &str,
    origin: usize,
    boundaries: &ScanBoundaries,
) -> PResult<Vec<Token>> {
    let mut s = Scanner::new(file, source, 0, 0, Vec::new());
    s.cached = Some(boundaries);
    s.boundary_origin = origin;
    s.virtual_paren = true;
    s.delimiters.push(b'(');
    s.opened.push(Pos::new(0, 1, 1));
    s.run(None)?;
    let closing = s.tokens.len() - 3;
    s.tokens.remove(closing);
    Ok(s.tokens)
}

/// For each physical line start (including the empty line after a final newline),
/// reports whether lexing the prefix ending there has an unterminated delimiter.
/// A different lexical error on a line makes all later prefixes false.
pub(crate) fn unterminated_prefixes(file: &Arc<str>, source: &str, stop_at: &[bool]) -> Vec<bool> {
    if source.starts_with('\u{feff}') {
        return vec![false; source.bytes().filter(|b| *b == b'\n').count() + 1];
    }
    let (normalized, offsets) = normalize_source(source);
    let mut scanner = Scanner::new(file, &normalized, 0, 0, offsets);
    let mut prefixes = Vec::with_capacity(source.bytes().filter(|b| *b == b'\n').count() + 1);
    let _ = scanner.run(Some((&mut prefixes, stop_at)));
    prefixes.resize(source.bytes().filter(|b| *b == b'\n').count() + 1, false);
    prefixes
}

impl<'a> Scanner<'a> {
    fn new(
        file: &'a Arc<str>,
        text: &'a str,
        base_offset: u32,
        base_line: u32,
        line_offsets: Vec<u32>,
    ) -> Self {
        Self {
            file,
            src: text.as_bytes(),
            text,
            offset: 0,
            line: base_line + 1,
            base_line,
            base_offset,
            column: 1,
            tokens: Vec::new(),
            levels: vec![Layout {
                indent: 0,
                depth: 0,
            }],
            delimiters: Vec::new(),
            groups: Vec::new(),
            opened: Vec::new(),
            function_depths: Vec::new(),
            line_offsets,
            interpolations: Vec::new(),
            boundaries: ScanBoundaries::default(),
            cached: None,
            boundary_origin: 0,
            virtual_paren: false,
        }
    }
}

/// Lexes raw bytes, reporting invalid UTF-8.
pub fn lex_bytes<'a>(file: &'a Arc<str>, source: &'a [u8]) -> PResult<Lexed<'a>> {
    match std::str::from_utf8(source) {
        Ok(text) => lex(file, text),
        Err(_) => Err(Box::new(Diagnostic::parse(
            file,
            Pos::new(0, 1, 1),
            "source must be valid UTF-8; re-save the file with UTF-8 encoding",
        ))),
    }
}

/// Replaces CRLF with LF and records, per normalised line, how many CR bytes
/// precede it, so positions can be reported in original-source offsets.
fn normalize_source(source: &str) -> (Cow<'_, str>, Vec<u32>) {
    if !source.contains("\r\n") {
        return (Cow::Borrowed(source), Vec::new());
    }
    let normalized = source.replace("\r\n", "\n");
    let bytes = source.as_bytes();
    let mut offsets = Vec::with_capacity(source.matches('\n').count() + 1);
    offsets.push(0u32);
    let mut removed = 0u32;
    for (at, &b) in bytes.iter().enumerate() {
        if b == b'\n' {
            if at > 0 && bytes[at - 1] == b'\r' {
                removed += 1;
            }
            offsets.push(removed);
        }
    }
    (Cow::Owned(normalized), offsets)
}

/// Quotes a character for messages, escaping what is not printable.
pub fn quote_rune(c: char) -> String {
    format!("{c:?}")
}

impl Scanner<'_> {
    fn pos(&self) -> Pos {
        let mut offset = self.offset as u32 + self.base_offset;
        if !self.line_offsets.is_empty() {
            offset += self.line_offsets[(self.line - self.base_line) as usize - 1];
        }
        Pos {
            offset,
            line: self.line,
            column: self.column,
        }
    }
    fn err(&self, pos: Pos, message: impl Into<String>) -> Box<Diagnostic> {
        Box::new(Diagnostic::parse(self.file, pos, message))
    }
    fn fail<T>(&self, message: impl Into<String>) -> PResult<T> {
        Err(self.err(self.pos(), message))
    }
    fn fail_at<T>(&self, pos: Pos, message: impl Into<String>) -> PResult<T> {
        Err(self.err(pos, message))
    }
    /// Reports a character whose first byte was just consumed. The cursor can
    /// be inside its UTF-8 encoding, so it is not itself a diagnostic boundary.
    fn fail_previous_byte<T>(&self, message: impl Into<String>) -> PResult<T> {
        let mut pos = self.pos();
        pos.offset -= 1;
        pos.column -= 1;
        self.fail_at(pos, message)
    }
    /// Fails on the single ASCII character at the cursor, with its range and,
    /// when one exists, the replacement that fixes it.
    fn fail_char<T>(&self, message: String, replacement: Option<&str>) -> PResult<T> {
        let pos = self.pos();
        let end = Pos::new(pos.offset + 1, pos.line, pos.column + 1);
        let mut d = self.err(pos, message);
        d.end = Some(end);
        d.fix = replacement.map(|r| DiagnosticFix {
            pos,
            end,
            replacement: r.to_string(),
        });
        Err(d)
    }
    /// Whether only whitespace or a `#` comment follows the cursor on its line.
    fn trailing_semicolon(&self) -> bool {
        let rest = &self.text[self.offset + 1..];
        let line = rest
            .split('\n')
            .next()
            .unwrap_or("")
            .trim_start_matches([' ', '\t']);
        line.is_empty() || line.starts_with('#') || line == "\r"
    }
    /// Fails on the source range `[start, cursor)`.
    fn fail_range<T>(&self, start: Pos, message: String) -> PResult<T> {
        let mut d = self.err(start, message);
        d.end = Some(self.pos());
        Err(d)
    }
    fn emit(&mut self, kind: Tok, lo: usize, hi: usize, pos: Pos) {
        let end = self.pos();
        self.tokens.push(Token {
            kind,
            pos,
            end,
            lo: lo as u32,
            hi: hi as u32,
        });
    }
    fn emit_layout(&mut self, kind: Tok) {
        let p = self.pos();
        let at = self.offset as u32;
        self.tokens.push(Token {
            kind,
            pos: p,
            end: p,
            lo: at,
            hi: at,
        });
    }
    fn advance(&mut self) -> u8 {
        let b = self.src[self.offset];
        self.offset += 1;
        if b == b'\n' {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        b
    }
    fn at(&self, i: usize) -> Option<u8> {
        self.src.get(i).copied()
    }

    fn run(&mut self, mut prefixes: Option<(&mut Vec<bool>, &[bool])>) -> PResult<()> {
        let n = self.src.len();
        let (mut pending, mut header_indent, mut pending_depth) = (false, 0usize, 0usize);
        // Where the pending header's statement began, when it spans several lines.
        let mut header_start = 0usize;
        // A line that starts with '.' or '|' continues the previous statement,
        // which began at statement_indent; it opens no block and ends no statement.
        let (mut continuing, mut statement_indent) = (false, 0usize);
        while self.offset < n {
            if let Some((prefixes, stop_at)) = prefixes.as_mut() {
                let open = !self.delimiters.is_empty();
                // Lines inside a multi-line text were consumed by one token.
                let line = (self.line - self.base_line - 1) as usize;
                while prefixes.len() < line {
                    prefixes.push(true);
                }
                prefixes.push(open);
                if stop_at.get(prefixes.len() - 1) == Some(&true) && !open {
                    return Ok(());
                }
            }
            let mut leading = 0usize;
            while self.offset < n && self.src[self.offset] == b' ' {
                self.advance();
                leading += 1;
            }
            if self.offset == n {
                break;
            }
            if self.src[self.offset] == b'\t' {
                return self.fail(
                    "tabs are not allowed in code; indent with four spaces per level (tabs may appear only inside text or comments)",
                );
            }
            if self.src[self.offset] == b'#' {
                self.skip_comment()?;
                if self.offset < n {
                    self.advance();
                }
                continue;
            }
            if self.src[self.offset] == b'\n' {
                self.advance();
                continue;
            }
            if !self.virtual_paren && !leading.is_multiple_of(4) {
                return self.fail(format!(
                    "indentation must be a multiple of four spaces, found {}; use {} or {}",
                    leading,
                    leading / 4 * 4,
                    leading / 4 * 4 + 4
                ));
            }
            if continuing {
                if leading != statement_indent + 4 {
                    return self.fail(format!(
                        "a line starting with '.' or '|' continues the previous statement and must be indented four spaces past it, to {} spaces, found {}",
                        statement_indent + 4,
                        leading
                    ));
                }
                continuing = false;
            } else {
                if self.delimiters.len() == self.levels.last().unwrap().depth {
                    statement_indent = leading;
                }
                let mut started_suite = false;
                if pending {
                    if leading == header_indent + 4 {
                        self.levels.push(Layout {
                            indent: leading,
                            depth: pending_depth,
                        });
                        self.emit_layout(Tok::Indent);
                        started_suite = true;
                    } else if leading > header_start && leading <= header_indent {
                        return self.fail(format!(
                            "a suite begins four spaces after the line that ends with ':' (at {} spaces); indent this line to {}, or move that closing line back to {} spaces",
                            header_indent,
                            header_indent + 4,
                            header_start
                        ));
                    } else if leading <= header_indent {
                        // An empty declaration suite has the same layout
                        // boundaries as a populated one.
                        self.emit_layout(Tok::Indent);
                        self.emit_layout(Tok::Dedent);
                    } else {
                        return self.fail(format!(
                            "a suite must begin exactly four spaces after its header; the header is at {} spaces, so indent this line to {}",
                            header_indent,
                            header_indent + 4
                        ));
                    }
                    pending = false;
                }
                if !started_suite {
                    // A continuation line inside delimiters opened within a level
                    // does not close that level; only suites opened inside the
                    // open delimiters can.
                    while self.levels.len() > 1 {
                        let top = self.levels.last().unwrap();
                        if !(leading < top.indent && top.depth >= self.delimiters.len()) {
                            break;
                        }
                        self.levels.pop();
                        self.emit_layout(Tok::Dedent);
                    }
                    let top = self.levels.last().unwrap();
                    let (top_indent, top_depth) = (top.indent, top.depth);
                    if self.delimiters.len() == top_depth && leading != top_indent {
                        if leading > top_indent {
                            if let Some(d) = self.missing_colon() {
                                return Err(d);
                            }
                            let hint = self.continuation_hint();
                            return self.fail(format!(
                                "unexpected indentation, {} spaces where {} are expected; the previous line must end with ':' to open a block (fn, if, else, for, while, match, type, impl headers), otherwise align this line with it{}",
                                leading, top_indent, hint
                            ));
                        }
                        return self.fail(format!(
                            "inconsistent dedent to {} spaces; enclosing blocks are indented at {} or {} spaces, so align with one of them",
                            leading,
                            top_indent,
                            top_indent.saturating_sub(4)
                        ));
                    }
                }
            }
            let (top_indent, top_depth) = {
                let t = self.levels.last().unwrap();
                (t.indent, t.depth)
            };
            if let Some(last) = self.tokens.last()
                && last.kind == Tok::Dedent
                && self.delimiters.len() == top_depth
            {
                self.emit_layout(Tok::Newline);
            }
            let line_start = self.tokens.len();
            while self.offset < n && self.src[self.offset] != b'\n' {
                let b = self.src[self.offset];
                let p = self.pos();
                if b == b' ' {
                    self.advance();
                    continue;
                }
                if b == b'#' {
                    self.skip_comment()?;
                    break;
                }
                if b == b'\t' || b == b'\r' {
                    return self.fail(
                        "tabs and lone carriage returns are not allowed in code; use spaces, and line endings of LF or CRLF",
                    );
                }
                if b == b'r' && self.src[self.offset + 1..].starts_with(b"\"\"\"") {
                    let start = self.offset;
                    self.scan_multiline(true)?;
                    self.emit(Tok::String, start, self.offset, p);
                    continue;
                }
                if letter(b) {
                    let start = self.offset;
                    let mut i = start;
                    while i < n && (letter(self.src[i]) || digit(self.src[i])) {
                        i += 1;
                    }
                    self.column += (i - start) as u32;
                    self.offset = i;
                    let kind = Tok::from_word(&self.text[start..i]);
                    if kind == Tok::Fn || kind == Tok::Match {
                        self.function_depths.push(self.delimiters.len());
                    }
                    self.emit(kind, start, i, p);
                    continue;
                }
                if digit(b) {
                    self.scan_number(p)?;
                    continue;
                }
                if b == b'"' {
                    let start = self.offset;
                    self.scan_string()?;
                    self.emit(Tok::String, start, self.offset, p);
                    continue;
                }
                if b == b'.'
                    && self.at(self.offset + 1) == Some(b'.')
                    && self.at(self.offset + 2) == Some(b'.')
                {
                    let start = self.offset;
                    self.advance();
                    self.advance();
                    self.advance();
                    self.emit(Tok::Ellipsis, start, start + 3, p);
                    continue;
                }
                let two = match (b, self.at(self.offset + 1)) {
                    (b'.', Some(b'.')) => Some(Tok::DotDot),
                    (b'-', Some(b'>')) => Some(Tok::Arrow),
                    (b'=', Some(b'=')) => Some(Tok::EqEq),
                    (b'!', Some(b'=')) => Some(Tok::NotEq),
                    (b'<', Some(b'=')) => Some(Tok::Le),
                    (b'>', Some(b'=')) => Some(Tok::Ge),
                    _ => None,
                };
                if let Some(kind) = two {
                    let start = self.offset;
                    self.advance();
                    self.advance();
                    self.emit(kind, start, start + 2, p);
                    continue;
                }
                // `!` directly after a type-ending character is the Result suffix of `T!`
                // or `T!E`; anywhere else it stays the removed negation.
                let result_suffix = b == b'!'
                    && self.offset > 0
                    && self.tokens.last().is_some_and(|t| {
                        matches!(
                            t.kind,
                            Tok::Name | Tok::RBracket | Tok::RParen | Tok::Question | Tok::Bang
                        )
                    })
                    && matches!(self.src[self.offset - 1], b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_' | b']' | b')' | b'?' | b'!');
                let kind = match b {
                    b'!' if result_suffix => Tok::Bang,
                    b'(' => Tok::LParen,
                    b')' => Tok::RParen,
                    b'[' => Tok::LBracket,
                    b']' => Tok::RBracket,
                    b'{' => Tok::LBrace,
                    b'}' => Tok::RBrace,
                    b':' => Tok::Colon,
                    b',' => Tok::Comma,
                    b'.' => Tok::Dot,
                    b'?' => Tok::Question,
                    b'+' => Tok::Plus,
                    b'-' => Tok::Minus,
                    b'*' => Tok::Star,
                    b'/' => Tok::Slash,
                    b'%' => Tok::Percent,
                    b'<' => Tok::Lt,
                    b'>' => Tok::Gt,
                    b'=' => Tok::Assign,
                    b'&' => Tok::Amp,
                    b'|' => Tok::Pipe,
                    _ => {
                        if b >= 0x80 {
                            let c = self.text[self.offset..].chars().next().unwrap();
                            return self.fail(format!(
                                "unexpected source character {}; non-ASCII characters are only allowed inside text and '#' comments, and identifiers are ASCII",
                                quote_rune(c)
                            ));
                        }
                        return self.fail_char(
                            format!(
                                "unexpected source character {}{}",
                                quote_rune(b as char),
                                character_hint(b)
                            ),
                            match b {
                                // Removing a mid-line `;` would fuse two statements.
                                b';' if self.trailing_semicolon() => Some(""),
                                b'!' => Some("not "),
                                _ => None,
                            },
                        );
                    }
                };
                if matches!(b, b'(' | b'[' | b'{') {
                    self.delimiters.push(b);
                    self.opened.push(p);
                    if b == b'('
                        && let Some(last) = self.tokens.last()
                        && (last.kind == Tok::Let || last.kind == Tok::Var)
                    {
                        self.groups.push(self.delimiters.len());
                    }
                }
                if matches!(b, b')' | b']' | b'}') {
                    if self.virtual_paren && self.delimiters == *b"(" && b == b')' {
                        // The physical wrapper would leave its own closing
                        // parenthesis unmatched; use that path for its exact error.
                        return self.fail("interpolation closes the virtual parenthesis");
                    }
                    if self.delimiters.is_empty() {
                        return self.fail(format!(
                            "unmatched closing delimiter '{}'; remove it or add the matching opener before it",
                            b as char
                        ));
                    }
                    if self.levels.len() > 1
                        && self.delimiters.len() <= top_depth
                        && leading >= top_indent
                    {
                        return self.fail("an outer delimiter cannot close inside a function suite; close the bracket on the line where the function body ends, or dedent the body");
                    }
                    let open = *self.delimiters.last().unwrap();
                    let want = match open {
                        b'(' => b')',
                        b'[' => b']',
                        _ => b'}',
                    };
                    if b != want {
                        let where_ = *self.opened.last().unwrap();
                        return self.fail(format!(
                            "mismatched closing delimiter '{}'; the '{}' opened at line {}:{} needs '{}'",
                            b as char, open as char, where_.line, where_.column, want as char
                        ));
                    }
                    if self.groups.last() == Some(&self.delimiters.len()) {
                        self.groups.pop();
                    }
                    self.delimiters.pop();
                    self.opened.pop();
                    while let Some(&d) = self.function_depths.last() {
                        if d > self.delimiters.len() {
                            self.function_depths.pop();
                        } else {
                            break;
                        }
                    }
                }
                let start = self.offset;
                self.advance();
                self.emit(kind, start, start + 1, p);
            }
            if self.virtual_paren && self.offset == n {
                if self.delimiters != *b"(" {
                    // The wrapper's closing parenthesis reports this error.
                    return self.fail("interpolation leaves a delimiter open");
                }
                self.delimiters.pop();
                self.opened.pop();
                self.groups.clear();
                self.function_depths.clear();
                self.emit_layout(Tok::RParen);
            }
            if self.tokens.len() > line_start {
                let last_kind = self.tokens.last().unwrap().kind;
                let has_function = self.function_depths.contains(&self.delimiters.len());
                if last_kind == Tok::Colon && (self.delimiters.len() == top_depth || has_function) {
                    pending = true;
                    header_indent = leading;
                    header_start = statement_indent;
                    pending_depth = self.delimiters.len();
                    self.emit_layout(Tok::Newline);
                    self.function_depths.clear();
                } else if self.delimiters.len() == top_depth {
                    self.function_depths.clear();
                    if self.continues_next() {
                        continuing = true;
                    } else {
                        self.emit_layout(Tok::Newline);
                    }
                } else if self.groups.last() == Some(&self.delimiters.len()) {
                    // A `let (` or `var (` group holds one binding per line, so
                    // its lines end like statements even though a delimiter is open.
                    self.emit_layout(Tok::Newline);
                }
            }
            if self.offset < n {
                self.advance();
            }
        }
        if pending {
            self.emit_layout(Tok::Indent);
            self.emit_layout(Tok::Dedent);
        }
        if let Some((prefixes, _)) = prefixes {
            prefixes.push(!self.delimiters.is_empty());
        }
        if let Some(&open) = self.delimiters.last() {
            let where_ = *self.opened.last().unwrap();
            let close = match open {
                b'(' => ')',
                b'[' => ']',
                _ => '}',
            };
            return self.fail(format!(
                "unterminated delimiter '{}' opened at line {}:{}; add the matching '{}' before the end of the file",
                open as char, where_.line, where_.column, close
            ));
        }
        while self.levels.len() > 1 {
            self.levels.pop();
            self.emit_layout(Tok::Dedent);
        }
        self.emit_layout(Tok::Eof);
        Ok(())
    }

    /// Reports whether the next code line begins with '.' or '|', which
    /// continues the statement on the current line. Blank and comment-only
    /// lines are skipped.
    fn continues_next(&self) -> bool {
        let n = self.src.len();
        let mut i = self.offset;
        if i >= n {
            return false;
        }
        i += 1;
        while i < n {
            let mut j = i;
            while j < n && self.src[j] == b' ' {
                j += 1;
            }
            if j >= n {
                return false;
            }
            match self.src[j] {
                b'\n' => i = j + 1,
                b'#' => {
                    while j < n && self.src[j] != b'\n' {
                        j += 1;
                    }
                    i = j + 1;
                }
                b'|' => return true,
                b'.' => return j + 1 < n && !digit(self.src[j + 1]) && self.src[j + 1] != b'.',
                _ => return false,
            }
        }
        false
    }

    /// Whether the UTF-8 sequence at `at` is a bidirectional text control (U+202A..U+202E,
    /// U+2066..U+2069), which can make source display differently from how it is read.
    fn bidi_control_at(&self, at: usize) -> bool {
        matches!(
            self.src.get(at..at + 3),
            Some([0xE2, 0x80, 0xAA..=0xAE] | [0xE2, 0x81, 0xA6..=0xA9])
        )
    }

    /// Consumes a comment through the end of its physical line.
    fn skip_comment(&mut self) -> PResult<()> {
        while self.offset < self.src.len() && self.src[self.offset] != b'\n' {
            if self.src[self.offset] == b'\r' {
                return self.fail("lone carriage returns are not allowed in comments; use line endings of LF or CRLF");
            }
            if self.bidi_control_at(self.offset) {
                return self.fail(BIDI_COMMENT);
            }
            self.advance();
        }
        Ok(())
    }

    /// Consumes digits accepted by `ok`, allowing `_` only between two digits. `after_digit` says
    /// whether a digit was just consumed, so a separator may follow immediately.
    fn scan_digits(&mut self, ok: fn(u8) -> bool, mut after_digit: bool) -> PResult<()> {
        let n = self.src.len();
        while self.offset < n {
            let b = self.src[self.offset];
            if ok(b) {
                after_digit = true;
            } else if b == b'_' {
                let next_ok = self.offset + 1 < n && ok(self.src[self.offset + 1]);
                if !after_digit || !next_ok {
                    return self.fail("a digit separator goes between two digits; write e.g. 1_000_000 or 0xFF_FF");
                }
                after_digit = false;
            } else {
                break;
            }
            self.advance();
        }
        Ok(())
    }

    fn scan_number(&mut self, p: Pos) -> PResult<()> {
        let n = self.src.len();
        let start = self.offset;
        self.advance();
        if self.src[start] == b'0' && self.offset < n {
            let radix: Option<fn(u8) -> bool> = match self.src[self.offset] {
                b'x' => Some(|b: u8| b.is_ascii_hexdigit()),
                b'b' => Some(|b: u8| b == b'0' || b == b'1'),
                _ => None,
            };
            if let Some(ok) = radix {
                self.advance();
                if self.offset == n || !ok(self.src[self.offset]) {
                    return self.fail("a hexadecimal or binary literal requires digits after the prefix; write e.g. 0xFF or 0b1010");
                }
                self.scan_digits(ok, false)?;
                if self.offset < n
                    && (letter(self.src[self.offset]) || digit(self.src[self.offset]))
                {
                    return self.fail("invalid digit in a hexadecimal or binary literal; 0x takes 0-9 and a-f, 0b takes 0 and 1");
                }
                self.emit(Tok::Number, start, self.offset, p);
                return Ok(());
            }
        }
        if self.src[start] == b'0'
            && self.offset < n
            && (digit(self.src[self.offset]) || self.src[self.offset] == b'_')
        {
            return self.fail("leading zeros are not allowed in numeric literals; write the number without them, e.g. 42 instead of 042");
        }
        self.scan_digits(digit, true)?;
        if self.offset + 1 < n && self.src[self.offset] == b'.' && digit(self.src[self.offset + 1])
        {
            self.advance();
            self.scan_digits(digit, false)?;
        }
        if self.offset < n && (self.src[self.offset] == b'e' || self.src[self.offset] == b'E') {
            self.advance();
            if self.offset < n && (self.src[self.offset] == b'+' || self.src[self.offset] == b'-') {
                self.advance();
            }
            if self.offset == n || !digit(self.src[self.offset]) {
                return self.fail("an exponent requires digits; write e.g. 1e3 or 2.5e-4");
            }
            while self.offset < n && digit(self.src[self.offset]) {
                self.advance();
            }
        }
        if self.offset < n && self.src[self.offset] == b'd' {
            self.advance();
        }
        if self.offset < n && letter(self.src[self.offset]) {
            while self.offset < n && (letter(self.src[self.offset]) || digit(self.src[self.offset]))
            {
                self.advance();
            }
            let word = &self.text[start..self.offset];
            let message = if word.len() > 1 && matches!(&word[..2], "0X" | "0B") {
                format!(
                    "invalid number {word}; the prefix is lowercase, so write {}{}",
                    word[..2].to_lowercase(),
                    &word[2..]
                )
            } else if word.len() > 1 && matches!(&word[..2], "0o" | "0O") {
                format!(
                    "invalid number {word}; octal literals do not exist, so write the value in decimal, hexadecimal (0x) or binary (0b)"
                )
            } else if word.contains('_') {
                format!(
                    "invalid number {word}; a digit separator goes between two digits of the integer or fraction part, e.g. 1_000_000"
                )
            } else {
                format!(
                    "invalid number {word}; the only numeric suffix is d for Decimal (1.5d), so put a space or operator after the number"
                )
            };
            return self.fail_range(p, message);
        }
        self.emit(Tok::Number, start, self.offset, p);
        Ok(())
    }

    fn scan_string(&mut self) -> PResult<()> {
        let start = self.offset;
        if self.src[start..].starts_with(b"\"\"\"") {
            return self.scan_multiline(false);
        }
        if let Some(end) = self
            .cached
            .and_then(|cache| cache.string_end(self.boundary_origin + start))
        {
            self.column += (end - self.boundary_origin - start) as u32;
            self.offset = end - self.boundary_origin;
            return Ok(());
        }
        let n = self.src.len();
        let opened = self.pos();
        self.advance();
        while self.offset < n {
            let b = self.advance();
            if b == b'"' {
                if !self.interpolations.is_empty() {
                    self.boundaries.strings.push((
                        self.boundary_origin + start,
                        self.boundary_origin + self.offset,
                    ));
                }
                return Ok(());
            }
            if b == b'\n' {
                if let Some(&at) = self.interpolations.last() {
                    return self.fail_at(at, format!("unterminated interpolation; the quote after this '{{' opens a nested text that never closes ({})", BRACE_HINT));
                }
                return self.fail_at(opened, "unterminated text literal; text must close with '\"' on the same line, so add the quote or write \\n for a line break");
            }
            if b < 32 {
                return self.fail("literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}");
            }
            if b == 0xE2 && self.bidi_control_at(self.offset - 1) {
                return self.fail_previous_byte(BIDI_TEXT);
            }
            if b == b'\\' {
                self.scan_escape()?;
            } else if b == b'{' {
                self.scan_interpolation()?;
            } else if b == b'}' {
                return self.fail("an unmatched closing brace must be escaped; write \\} for a literal brace (and \\{ for the opening brace), or open an interpolation with {expression}");
            }
        }
        self.fail("unterminated text literal")
    }

    /// Scans `"""` text (and `r"""` raw text when `raw`): the opening quotes end
    /// their line, the closing quotes start theirs, and every content line
    /// carries the closing line's indentation.
    fn scan_multiline(&mut self, raw: bool) -> PResult<()> {
        let opened = self.pos();
        if !self.interpolations.is_empty() {
            return self.fail("multi-line text cannot appear inside an interpolation; bind it to a name first and interpolate the name");
        }
        let n = self.src.len();
        for _ in 0..if raw { 4 } else { 3 } {
            self.advance();
        }
        if self.offset == n || self.src[self.offset] != b'\n' {
            return self.fail_at(opened, "multi-line text must start on the line after its opening '\"\"\"'; add a line break after the opening quotes");
        }
        let mut line_start = self.offset + 1;
        let mut lines: Vec<(usize, Pos)> = Vec::new();
        while self.offset < n {
            let b = self.advance();
            if b == b'\n' {
                line_start = self.offset;
                lines.push((line_start, self.pos()));
                continue;
            }
            if b == b'"' && self.src[self.offset..].starts_with(b"\"\"") {
                let quote = self.offset - 1;
                let indent = &self.src[line_start..quote];
                if !indent.iter().all(|&c| c == b' ' || c == b'\t') {
                    return self.fail_previous_byte("multi-line text closes with '\"\"\"' alone on its own line; move the closing quotes to a new line (a '\"\"\"' inside the text is not allowed, so write \\\" for a quote in non-raw text)");
                }
                for &(at, pos) in &lines {
                    let rest = &self.src[at..];
                    let line = &rest[..rest.iter().position(|&c| c == b'\n').unwrap_or(rest.len())];
                    let blank = line.iter().all(|&c| c == b' ' || c == b'\t');
                    if at < quote && !blank && !line.starts_with(indent) {
                        return self.fail_at(pos, "text line is indented less than the closing '\"\"\"'; indent it to the closing quotes' column, or move the closing quotes left");
                    }
                }
                self.advance();
                self.advance();
                return Ok(());
            }
            if b < 32 && b != b'\t' {
                return self.fail("literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}");
            }
            if b == 0xE2 && self.bidi_control_at(self.offset - 1) {
                return self.fail_previous_byte(BIDI_TEXT);
            }
            if raw {
                continue;
            }
            if b == b'\\' {
                self.scan_escape()?;
            } else if b == b'{' {
                self.scan_interpolation()?;
            } else if b == b'}' {
                return self.fail("an unmatched closing brace must be escaped; write \\} for a literal brace (and \\{ for the opening brace), or open an interpolation with {expression}");
            }
        }
        self.fail_at(
            opened,
            "unterminated multi-line text; close it with '\"\"\"' alone on its own line",
        )
    }

    /// Validates the escape after a consumed backslash.
    fn scan_escape(&mut self) -> PResult<()> {
        let n = self.src.len();
        let mut backslash = self.pos();
        backslash.column -= 1;
        backslash.offset -= 1;
        if self.offset == n {
            return self.fail(
                "unterminated text escape; a backslash needs a following character, e.g. \\n",
            );
        }
        let c = self.advance();
        if c == b'u' {
            if self.offset == n || self.advance() != b'{' {
                let message = "Unicode escapes use \\u{H}; write 1 to 6 hexadecimal digits in braces, e.g. \\u{1F600}";
                return if self.src[self.offset - 1].is_ascii() {
                    self.fail(message)
                } else {
                    self.fail_previous_byte(message)
                };
            }
            let start = self.offset;
            let mut value: u64 = 0;
            while self.offset < n && self.src[self.offset] != b'}' {
                let c = self.advance();
                let d = match c {
                    b'0'..=b'9' => (c - b'0') as u64,
                    b'a'..=b'f' => (c - b'a') as u64 + 10,
                    b'A'..=b'F' => (c - b'A') as u64 + 10,
                    _ => {
                        let message = "invalid Unicode scalar escape; use only hexadecimal digits 0-9 and a-f inside \\u{...}";
                        return if c.is_ascii() {
                            self.fail(message)
                        } else {
                            self.fail_previous_byte(message)
                        };
                    }
                };
                value = value.saturating_mul(16).saturating_add(d);
            }
            let digits = self.offset - start;
            if self.offset == n
                || !(1..=6).contains(&digits)
                || value > 0x10ffff
                || (0xd800..=0xdfff).contains(&value)
            {
                return self.fail("invalid Unicode scalar escape; use 1 to 6 hexadecimal digits for a value up to 10FFFF that is not a surrogate (D800-DFFF)");
            }
            self.advance();
        } else if !b"\"\\nrt{}".contains(&c) {
            let escape = if c.is_ascii_graphic() {
                format!(" \\{}", char::from(c))
            } else {
                let full = self.text[self.offset - 1..].chars().next().unwrap();
                format!(": a backslash followed by {}", quote_rune(full))
            };
            return self.fail_at(backslash, format!("unknown text escape{escape}; valid escapes are \\n \\t \\r \\\\ \\\" \\{{ \\}} and \\u{{H}}"));
        }
        Ok(())
    }

    fn scan_interpolation(&mut self) -> PResult<()> {
        let start = self.boundary_origin + self.offset - 1;
        let mut open = self.pos();
        open.column -= 1;
        open.offset -= 1;
        if self.interpolations.len() >= MAX_INTERPOLATION_DEPTH {
            return self.fail_at(open, format!("nesting exceeds {} levels; split the expression, type, or block into named parts", MAX_INTERPOLATION_DEPTH));
        }
        self.interpolations.push(open);
        let result = self.interpolation_body(open);
        self.interpolations.pop();
        if result.is_ok() {
            self.boundaries
                .interpolations
                .push((start, self.boundary_origin + self.offset));
        }
        result
    }

    fn interpolation_body(&mut self, open: Pos) -> PResult<()> {
        let n = self.src.len();
        let mut depth = 1;
        let start = self.offset;
        while self.offset < n {
            let b = self.src[self.offset];
            if b == b'\n' || b == b'\r' || b == b'#' {
                return self.fail_at(open, format!("newlines and comments are not allowed inside interpolation; keep the expression on one line, or bind it to a name first and interpolate the name ({})", BRACE_HINT));
            }
            if b == b'\\' {
                return self.fail_at(
                    open,
                    format!(
                        "{}; a backslash cannot appear in the interpolated expression",
                        BRACE_HINT
                    ),
                );
            }
            if b == b'"' {
                self.scan_string()?;
                continue;
            }
            self.advance();
            if b == b'{' {
                depth += 1;
            }
            if b == b'}' {
                depth -= 1;
                if depth == 0 {
                    if self.text[start..self.offset - 1]
                        .trim_matches(char::is_whitespace)
                        .is_empty()
                    {
                        return self.fail("empty interpolation; put an expression between the braces, or write \\{ for a literal brace");
                    }
                    return Ok(());
                }
            }
        }
        self.fail_at(
            open,
            format!(
                "unterminated interpolation; add the closing }} before the closing quote ({})",
                BRACE_HINT
            ),
        )
    }

    /// A block header on the previous line that lacks its closing ':' when an
    /// indented line follows it, with the fix that inserts the ':'.
    fn missing_colon(&self) -> Option<Box<Diagnostic>> {
        let real = |t: &&Token| !matches!(t.kind, Tok::Newline | Tok::Comment);
        let last = self.tokens.iter().rev().find(real)?;
        if last.kind == Tok::Colon || matches!(last.kind, Tok::Indent | Tok::Dedent) {
            return None;
        }
        let first = self
            .tokens
            .iter()
            .rev()
            .skip_while(|t| t.kind == Tok::Newline)
            .take_while(|t| !matches!(t.kind, Tok::Newline | Tok::Indent | Tok::Dedent))
            .last()?;
        if first.pos.line != last.end.line
            || !matches!(
                first.kind,
                Tok::Fn
                    | Tok::If
                    | Tok::Else
                    | Tok::For
                    | Tok::While
                    | Tok::Match
                    | Tok::Type
                    | Tok::Impl
                    | Tok::Test
                    | Tok::Interface
            )
        {
            return None;
        }
        let mut d = self.err(
            last.end,
            format!(
                "the '{}' block header on line {} does not end with ':'; add ':' at the end of that line so the indented lines below become its body",
                first.kind.as_str(),
                first.pos.line
            ),
        );
        d.end = Some(last.end);
        d.fix = Some(DiagnosticFix {
            pos: last.end,
            end: last.end,
            replacement: ":".into(),
        });
        Some(d)
    }

    /// Explains the usual cause of an over-indented line that starts with a
    /// binary operator: the previous expression ended at the newline.
    fn continuation_hint(&self) -> String {
        for t in self.tokens.iter().rev() {
            match t.kind {
                Tok::Newline | Tok::Indent | Tok::Dedent => continue,
                Tok::Pipe => {
                    return "; a pipe step cannot follow the '|' on the next line, so end the previous line before '|' and start the continuation line with '|'".to_string();
                }
                _ => break,
            }
        }
        let rest = &self.text[self.offset..];
        let end = rest.find([' ', '\n']).unwrap_or(rest.len());
        match &rest[..end] {
            "and" | "or" | "+" | "-" | "*" | "/" | "%" | "==" | "!=" | "<" | ">" | "<=" | ">=" => {
                "; to continue an expression on the next line, wrap the whole expression in parentheses".to_string()
            }
            _ => String::new(),
        }
    }
}

/// Explains the common foreign-syntax characters.
fn character_hint(b: u8) -> &'static str {
    match b {
        b';' => "; Manuscript ends a statement at the end of the line, so remove the semicolon",
        b'\'' => "; text uses double quotes, e.g. \"text\"",
        b'!' => "; write 'not x' for negation and '!=' for inequality",
        b'`' => "; text uses double quotes with {expression} interpolation",
        b'$' | b'@' | b'\\' | b'^' | b'~' => {
            "; this character is not part of Manuscript's syntax outside text"
        }
        _ => "; this character is not part of Manuscript's syntax",
    }
}
