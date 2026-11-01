//! The source excerpt printed under a terminal diagnostic: the offending line
//! with a caret underline beneath its span.

use std::collections::HashMap;

const TAB_WIDTH: usize = 4;

/// Reads each source file once for the snippets of one report.
#[derive(Default)]
pub struct Sources {
    files: HashMap<String, Option<Source>>,
}

impl Sources {
    /// The excerpt for the span `line:column` to `end` in `file`, or an empty
    /// string when the file is unreadable (a bundled standard-library file).
    /// `end` is `(line, column)`; columns are 1-based byte columns.
    pub fn excerpt(
        &mut self,
        file: &str,
        line: usize,
        column: usize,
        end: Option<(usize, usize)>,
    ) -> String {
        let text = self
            .files
            .entry(file.to_string())
            .or_insert_with(|| std::fs::read_to_string(file).ok().map(Source::new));
        match text {
            Some(text) => text.excerpt(line, column, end),
            None => String::new(),
        }
    }
}

/// Original text and line boundaries retained for one report.
struct Source {
    text: String,
    starts: Vec<usize>,
}

impl Source {
    fn new(text: String) -> Self {
        let mut starts = vec![0];
        starts.extend(text.match_indices('\n').map(|(at, _)| at + 1));
        Self { text, starts }
    }

    fn excerpt(&self, line: usize, column: usize, end: Option<(usize, usize)>) -> String {
        let Some(index) = line.checked_sub(1) else {
            return String::new();
        };
        let Some(&start) = self.starts.get(index) else {
            return String::new();
        };
        let stop = self
            .starts
            .get(index + 1)
            .map_or(self.text.len(), |at| at - 1);
        render(&self.text[start..stop], line, column, end)
    }
}

fn render(raw: &str, line: usize, column: usize, end: Option<(usize, usize)>) -> String {
    let source = raw.strip_suffix('\r').unwrap_or(raw);
    let start = source.floor_char_boundary(column.saturating_sub(1));
    let stop = match end {
        Some((end_line, end_column)) if end_line == line => {
            source.floor_char_boundary(end_column.saturating_sub(1))
        }
        Some((end_line, _)) if end_line > line => source.len(),
        _ => start,
    };
    let indent = width(&source[..start]);
    let marks = width(&source[start..stop.max(start)]).max(1);
    let number = line.to_string();
    let gutter = " ".repeat(number.len());
    format!(
        "\n {gutter} |\n {number} | {}\n {gutter} | {}{}",
        expand(source),
        " ".repeat(indent),
        "^".repeat(marks)
    )
}

fn expand(text: &str) -> String {
    text.replace('\t', &" ".repeat(TAB_WIDTH))
}

/// Terminal cells `text` occupies, with tabs at a fixed width.
fn width(text: &str) -> usize {
    text.chars().map(cell_width).sum()
}

fn cell_width(c: char) -> usize {
    match c {
        '\t' => TAB_WIDTH,
        '\u{200b}'..='\u{200f}' | '\u{0300}'..='\u{036f}' | '\u{fe00}'..='\u{fe0f}' => 0,
        '\u{1100}'..='\u{115f}'
        | '\u{2e80}'..='\u{a4cf}'
        | '\u{ac00}'..='\u{d7a3}'
        | '\u{f900}'..='\u{faff}'
        | '\u{fe30}'..='\u{fe6f}'
        | '\u{ff00}'..='\u{ff60}'
        | '\u{ffe0}'..='\u{ffe6}'
        | '\u{1f300}'..='\u{1f64f}'
        | '\u{1f900}'..='\u{1f9ff}'
        | '\u{20000}'..='\u{3fffd}' => 2,
        _ => 1,
    }
}

#[cfg(test)]
mod tests {
    use super::Source;

    fn render(text: &str, line: usize, column: usize, end: Option<(usize, usize)>) -> String {
        Source::new(text.to_string()).excerpt(line, column, end)
    }

    #[test]
    fn indexed_lines_preserve_original_excerpts_in_any_order() {
        for text in ["", "a", "a\n", "\n\r\n\t日本😀e\u{301}\r\nlast"] {
            let source = Source::new(text.to_string());
            for line in (0..=text.split('\n').count() + 1).rev() {
                for column in 0..=text.len() + 2 {
                    let expected = line
                        .checked_sub(1)
                        .and_then(|i| text.split('\n').nth(i))
                        .map_or_else(String::new, |raw| {
                            super::render(raw, line, column, Some((line, column + 3)))
                        });
                    assert_eq!(
                        source.excerpt(line, column, Some((line, column + 3))),
                        expected
                    );
                }
            }
        }
    }

    #[test]
    fn many_lines_share_one_index() {
        let text: String = (0..8000).map(|i| format!("line {i}\r\n")).collect();
        let source = Source::new(text);
        assert_eq!(source.starts.len(), 8001);
        for line in (1..=8000).rev() {
            assert!(
                source
                    .excerpt(line, 1, None)
                    .contains(&format!("line {}", line - 1))
            );
        }
        assert_eq!(source.starts.len(), 8001);
        assert!(source.excerpt(usize::MAX, 1, None).is_empty());
    }

    #[test]
    fn underlines_the_span() {
        let out = render("let x = foo(1)\n", 1, 9, Some((1, 12)));
        assert_eq!(out, "\n   |\n 1 | let x = foo(1)\n   |         ^^^");
    }

    #[test]
    fn point_diagnostic_gets_one_caret() {
        assert!(render("abc\n", 1, 2, None).ends_with("|  ^"));
    }

    #[test]
    fn tabs_and_crlf() {
        let out = render("\tx = 1\r\ny\r\n", 1, 2, Some((1, 3)));
        assert_eq!(out, "\n   |\n 1 |     x = 1\n   |     ^");
    }

    #[test]
    fn wide_characters_shift_the_caret() {
        let out = render("\"日本\" + 1\n", 1, 10, Some((1, 11)));
        assert!(out.ends_with("|        ^"), "{out}");
    }

    #[test]
    fn multiline_span_underlines_to_line_end() {
        let out = render("ab cd\nef\n", 1, 4, Some((2, 2)));
        assert!(out.ends_with("|    ^^"), "{out}");
    }

    #[test]
    fn missing_line_is_empty() {
        assert_eq!(render("a\n", 5, 1, None), "");
    }
}
