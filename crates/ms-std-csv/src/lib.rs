//! `@std/csv.ms` natives. The reader is a port of Go's `encoding/csv` in its strict
//! configuration (no lazy quotes, no comments, variable record width), and the writer follows
//! `pkg/runtime/csv.go`, which is the behavioral oracle.
#![no_std]

extern crate alloc;

pub mod ffi;

use alloc::string::String;
use alloc::vec::Vec;
use ms_std_core::Fail;

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

struct Lines<'a> {
    text: &'a [u8],
    at: usize,
}

impl<'a> Lines<'a> {
    /// Next line with a CRLF terminator folded to LF; `None` at end of input.
    fn next(&mut self) -> Option<Vec<u8>> {
        if self.at >= self.text.len() {
            return None;
        }
        let rest = &self.text[self.at..];
        let (mut line, ended) = match rest.iter().position(|&b| b == b'\n') {
            Some(i) => (rest[..=i].to_vec(), true),
            None => (rest.to_vec(), false),
        };
        self.at += line.len();
        if !ended && line.last() == Some(&b'\r') {
            line.pop();
        }
        let n = line.len();
        if n >= 2 && line[n - 2] == b'\r' && line[n - 1] == b'\n' {
            line[n - 2] = b'\n';
            line.pop();
        }
        Some(line)
    }
}

fn nl_len(b: &[u8]) -> usize {
    usize::from(b.last() == Some(&b'\n'))
}

/// Reads one record; `Ok(None)` at end of input.
fn read_record(lines: &mut Lines, comma: u8) -> Result<Option<Vec<String>>, Fail> {
    let mut line = loop {
        match lines.next() {
            None => return Ok(None),
            Some(l) if l.len() == nl_len(&l) => continue,
            Some(l) => break l,
        }
    };
    let mut buf: Vec<u8> = Vec::new();
    let mut ends: Vec<usize> = Vec::new();
    let mut at = 0usize; // consumed prefix of `line`
    loop {
        let rest = &line[at..];
        if rest.first() != Some(&b'"') {
            let i = rest.iter().position(|&b| b == comma);
            let field = match i {
                Some(i) => &rest[..i],
                None => &rest[..rest.len() - nl_len(rest)],
            };
            if field.contains(&b'"') {
                return Err(Fail::InvalidData);
            }
            buf.extend_from_slice(field);
            ends.push(buf.len());
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
            let rest = &line[at..];
            match rest.iter().position(|&b| b == b'"') {
                Some(i) => {
                    buf.extend_from_slice(&rest[..i]);
                    at += i + 1;
                    let after = &line[at..];
                    match after.first() {
                        Some(b'"') => {
                            buf.push(b'"');
                            at += 1;
                        }
                        Some(&c) if c == comma => {
                            at += 1;
                            ends.push(buf.len());
                            break;
                        }
                        _ if after.len() == nl_len(after) => {
                            ends.push(buf.len());
                            return finish(buf, ends).map(Some);
                        }
                        _ => return Err(Fail::InvalidData),
                    }
                }
                None if !rest.is_empty() => {
                    buf.extend_from_slice(rest);
                    line = match lines.next() {
                        Some(l) => l,
                        None => return Err(Fail::InvalidData),
                    };
                    at = 0;
                }
                None => return Err(Fail::InvalidData),
            }
        }
    }
    finish(buf, ends).map(Some)
}

fn finish(buf: Vec<u8>, ends: Vec<usize>) -> Result<Vec<String>, Fail> {
    let text = String::from_utf8(buf).map_err(|_| Fail::InvalidData)?;
    let mut out = Vec::with_capacity(ends.len());
    let mut prev = 0;
    for e in ends {
        out.push(String::from(&text[prev..e]));
        prev = e;
    }
    Ok(out)
}

/// Parses CSV into rows. The row and cell budgets are strict limits, not truncation.
pub fn parse(
    text: &str,
    opts: Options,
    max_rows: Option<i64>,
    max_cells: Option<i64>,
) -> Result<Vec<Vec<String>>, Fail> {
    let rows_budget = budget(max_rows)?;
    let cells_budget = budget(max_cells)?;
    let mut lines = Lines {
        text: text.as_bytes(),
        at: 0,
    };
    let mut rows: Vec<Vec<String>> = Vec::new();
    let mut cells = 0usize;
    while let Some(record) = read_record(&mut lines, opts.delimiter)? {
        if rows.len() >= rows_budget || record.len() > cells_budget - cells {
            return Err(Fail::LimitExceeded);
        }
        cells += record.len();
        rows.push(record);
    }
    Ok(rows)
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
