//! `@std/csv.ms` natives. The reader is strict (no lazy quotes,
//! no comments, variable record width).
#![no_std]

extern crate alloc;

pub mod ffi;

use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::{Fail, StringTable};

/// Validated `CsvOptions`.
#[derive(Clone, Copy, Debug)]
pub struct Options {
    pub delimiter: u8,
    pub crlf: bool,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            delimiter: b',',
            crlf: false,
        }
    }
}

/// Validates the delimiter (one ASCII byte other than quote, CR, LF, NUL) and the line ending.
pub fn options(delimiter: &str, line_ending: &str) -> Result<Options, Fail> {
    let d = delimiter.as_bytes();
    if d.len() != 1 || d[0] >= 128 || matches!(d[0], b'"' | b'\r' | b'\n' | 0) {
        return Err(Fail::InvalidInput);
    }
    if line_ending != "\n" && line_ending != "\r\n" {
        return Err(Fail::InvalidInput);
    }
    Ok(Options {
        delimiter: d[0],
        crlf: line_ending == "\r\n",
    })
}

fn budget(max: Option<i64>) -> Result<usize, Fail> {
    match max {
        None => Ok(usize::MAX),
        Some(n) if n < 0 => Err(Fail::InvalidInput),
        Some(n) => Ok(n as usize),
    }
}

/// A line of the input without its terminator; a CRLF terminator counts as one newline.
struct Line {
    start: usize,
    end: usize,
    /// Whether a newline ended the line (false only for the last line of input).
    ended: bool,
}

struct Lines<'a> {
    text: &'a [u8],
    at: usize,
}

impl Lines<'_> {
    /// Next line; `None` at end of input.
    fn next(&mut self) -> Option<Line> {
        if self.at >= self.text.len() {
            return None;
        }
        let start = self.at;
        let rest = &self.text[start..];
        let (mut end, ended) = match rest.iter().position(|&b| b == b'\n') {
            Some(i) => {
                self.at = start + i + 1;
                (start + i, true)
            }
            None => {
                self.at = self.text.len();
                (self.text.len(), false)
            }
        };
        if end > start && self.text[end - 1] == b'\r' {
            end -= 1;
        }
        Some(Line { start, end, ended })
    }
}

struct Reader<'a> {
    src: &'a str,
    lines: Lines<'a>,
    comma: u8,
    out: StringTable,
}

impl Reader<'_> {
    fn push(&mut self, from: usize, to: usize) -> Result<(), Fail> {
        // Offsets sit next to ASCII delimiters, so a miss means malformed input rather than a
        // split character.
        self.out
            .push_str(self.src.get(from..to).ok_or(Fail::InvalidData)?);
        Ok(())
    }

    fn end_cell(&mut self) {
        self.out.end_cell();
    }

    /// Reads one record into the table, returning its cell count; `Ok(None)` at end of input.
    fn record(&mut self) -> Result<Option<usize>, Fail> {
        let mut line = loop {
            match self.lines.next() {
                None => return Ok(None),
                Some(l) if l.start == l.end => continue,
                Some(l) => break l,
            }
        };
        let first = self.out.cells();
        let mut at = line.start; // consumed prefix of the line
        loop {
            let body = &self.lines.text[at..line.end];
            if body.first() != Some(&b'"') {
                let i = body.iter().position(|&b| b == self.comma);
                let field = &body[..i.unwrap_or(body.len())];
                if field.contains(&b'"') {
                    return Err(Fail::InvalidData);
                }
                self.push(at, at + field.len())?;
                self.end_cell();
                match i {
                    Some(i) => {
                        at += i + 1;
                        continue;
                    }
                    None => break,
                }
            }
            at += 1;
            loop {
                let body = &self.lines.text[at..line.end];
                match body.iter().position(|&b| b == b'"') {
                    Some(i) => {
                        self.push(at, at + i)?;
                        at += i + 1;
                        match self.lines.text[at..line.end].first() {
                            Some(b'"') => {
                                self.out.push_str("\"");
                                at += 1;
                            }
                            Some(&c) if c == self.comma => {
                                at += 1;
                                self.end_cell();
                                break;
                            }
                            None => {
                                self.end_cell();
                                return Ok(Some(self.out.cells() - first));
                            }
                            _ => return Err(Fail::InvalidData),
                        }
                    }
                    None if line.ended => {
                        // The quoted field continues on the next line.
                        self.push(at, line.end)?;
                        self.out.push_str("\n");
                        line = self.lines.next().ok_or(Fail::InvalidData)?;
                        at = line.start;
                    }
                    None => return Err(Fail::InvalidData),
                }
            }
        }
        Ok(Some(self.out.cells() - first))
    }
}

/// Parses CSV into a table. The row and cell budgets are strict limits, not truncation.
pub fn parse_table(
    text: &str,
    opts: Options,
    max_rows: Option<i64>,
    max_cells: Option<i64>,
) -> Result<StringTable, Fail> {
    let rows_budget = budget(max_rows)?;
    let cells_budget = budget(max_cells)?;
    let mut reader = Reader {
        src: text,
        lines: Lines {
            text: text.as_bytes(),
            at: 0,
        },
        comma: opts.delimiter,
        out: StringTable::default(),
    };
    let mut cells = 0usize;
    while let Some(count) = reader.record()? {
        if reader.out.row_count() >= rows_budget || count > cells_budget - cells {
            return Err(Fail::LimitExceeded);
        }
        cells += count;
        reader.out.end_row();
    }
    Ok(reader.out)
}

/// Parses CSV into rows.
pub fn parse(
    text: &str,
    opts: Options,
    max_rows: Option<i64>,
    max_cells: Option<i64>,
) -> Result<Vec<Vec<String>>, Fail> {
    parse_table(text, opts, max_rows, max_cells).map(StringTable::into_rows)
}

fn field_needs_quotes(field: &str, delim: u8) -> bool {
    let Some(first) = field.chars().next() else {
        return false;
    };
    field == "\\."
        || field
            .bytes()
            .any(|b| matches!(b, b'"' | b'\r' | b'\n') || b == delim)
        || first.is_whitespace()
}

fn push_field(out: &mut String, field: &str, delim: u8, crlf: bool) {
    if !field_needs_quotes(field, delim) {
        out.push_str(field);
        return;
    }
    let mut f = field.replace('"', "\"\"");
    if crlf {
        f = f.replace("\r\n", "\n").replace('\n', "\r\n");
    }
    out.push('"');
    out.push_str(&f);
    out.push('"');
}

/// Encodes rows; each row ends with the selected terminator. A row holding one empty cell is
/// written as `""` so that it parses back as a row. `max_bytes` bounds the whole output.
pub fn stringify<R: AsRef<[S]>, S: AsRef<str>>(
    rows: &[R],
    opts: Options,
    max_bytes: Option<i64>,
) -> Result<String, Fail> {
    let max = budget(max_bytes)?;
    let ending = if opts.crlf { "\r\n" } else { "\n" };
    let mut out = String::new();
    let mut line = String::new();
    for row in rows {
        let row = row.as_ref();
        line.clear();
        if row.len() == 1 && row[0].as_ref().is_empty() {
            line.push_str("\"\"");
        } else {
            for (i, f) in row.iter().enumerate() {
                if i > 0 {
                    line.push(opts.delimiter as char);
                }
                push_field(&mut line, f.as_ref(), opts.delimiter, opts.crlf);
            }
        }
        line.push_str(ending);
        if line.len() > max - out.len() {
            return Err(Fail::LimitExceeded);
        }
        out.push_str(&line);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    extern crate std;
    use super::*;

    fn p(text: &str) -> Result<Vec<Vec<String>>, Fail> {
        parse(text, Options::default(), None, None)
    }

    fn rows(r: &[&[&str]]) -> Vec<Vec<String>> {
        r.iter()
            .map(|row| row.iter().map(|s| String::from(*s)).collect())
            .collect()
    }

    #[test]
    fn parses_like_go() {
        assert_eq!(p("a,b\nc,d\n").unwrap(), rows(&[&["a", "b"], &["c", "d"]]));
        assert_eq!(p("a,b\r\nc").unwrap(), rows(&[&["a", "b"], &["c"]]));
        assert_eq!(p("\n\na\n\n").unwrap(), rows(&[&["a"]]));
        assert_eq!(p("").unwrap(), rows(&[]));
        assert_eq!(
            p("\"a,b\",\"c\"\"d\"\n").unwrap(),
            rows(&[&["a,b", "c\"d"]])
        );
        assert_eq!(p("\"a\nb\",c\n").unwrap(), rows(&[&["a\nb", "c"]]));
        assert_eq!(p("\"a\r\nb\"\n").unwrap(), rows(&[&["a\nb"]]));
        assert_eq!(p("a,,\n").unwrap(), rows(&[&["a", "", ""]]));
        assert_eq!(p("a,b\nc\n").unwrap(), rows(&[&["a", "b"], &["c"]]));
        assert_eq!(p("a\rb\n").unwrap(), rows(&[&["a\rb"]]));
        assert_eq!(p("\"\"\n").unwrap(), rows(&[&[""]]));
        assert_eq!(p("a, b\n").unwrap(), rows(&[&["a", " b"]]));
    }

    #[test]
    fn rejects_bad_quotes() {
        assert_eq!(p("a\"b\n"), Err(Fail::InvalidData));
        assert_eq!(p("\"a\n"), Err(Fail::InvalidData));
        assert_eq!(p("\"a\"b\n"), Err(Fail::InvalidData));
        assert_eq!(p("\"a"), Err(Fail::InvalidData));
    }

    #[test]
    fn budgets() {
        let o = Options::default();
        assert_eq!(parse("a\nb\n", o, Some(1), None), Err(Fail::LimitExceeded));
        assert_eq!(parse("a,b\n", o, None, Some(1)), Err(Fail::LimitExceeded));
        assert!(parse("a,b\n", o, Some(1), Some(2)).is_ok());
        assert_eq!(parse("a", o, Some(-1), None), Err(Fail::InvalidInput));
    }

    #[test]
    fn options_validate() {
        assert!(options(";", "\r\n").is_ok());
        for bad in ["", ",,", "\"", "\n", "\r", "\0", "é"] {
            assert_eq!(
                options(bad, "\n").err(),
                Some(Fail::InvalidInput),
                "{bad:?}"
            );
        }
        assert_eq!(options(",", "\r").err(), Some(Fail::InvalidInput));
    }

    #[test]
    fn stringifies() {
        let o = Options::default();
        let r = rows(&[&["a", "b,c", "d\"e", ""], &[""], &[" lead", "\\."]]);
        let s = stringify(&r, o, None).unwrap();
        assert_eq!(s, "a,\"b,c\",\"d\"\"e\",\n\"\"\n\" lead\",\"\\.\"\n");
        assert_eq!(p(&s).unwrap(), r);
        let crlf = Options { crlf: true, ..o };
        assert_eq!(
            stringify(&rows(&[&["a\nb", "c"]]), crlf, None).unwrap(),
            "\"a\r\nb\",c\r\n"
        );
        assert_eq!(
            stringify(&rows(&[&["abc"]]), o, Some(3)),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(stringify(&rows(&[&["abc"]]), o, Some(4)).unwrap(), "abc\n");
        assert_eq!(
            stringify::<Vec<String>, String>(&[], o, Some(-1)),
            Err(Fail::InvalidInput)
        );
    }
}
