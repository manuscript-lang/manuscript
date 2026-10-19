//! Source positions.

/// A position in a source file, as the Go implementation reports it.
///
/// `line` and `column` are 1-based; `column` counts **bytes** within the line
/// (not characters), and `offset` is the 0-based byte offset into the original
/// source text (before CRLF normalisation). A `line` of 0 means "no position".
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Pos {
    /// Byte offset into the original source.
    pub offset: u32,
    /// 1-based line number; 0 means unset.
    pub line: u32,
    /// 1-based byte column within the line.
    pub column: u32,
}

impl Pos {
    /// Creates a position.
    pub const fn new(offset: u32, line: u32, column: u32) -> Pos {
        Pos {
            offset,
            line,
            column,
        }
    }
}

/// A half-open byte range `[start, end)` of source.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq, Hash)]
pub struct Span {
    /// First byte of the range.
    pub start: u32,
    /// One past the last byte of the range.
    pub end: u32,
}
