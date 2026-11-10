//! Doc-comment extraction: the `//` lines and `/* */` blocks directly above a declaration, and a
//! trailing `//` on its line.

/// The columns of leading whitespace in `line`, a tab counting four.
pub fn indent_columns(line: &str) -> usize {
    line.chars()
        .take_while(|c| matches!(c, ' ' | '\t'))
        .map(|c| if c == '\t' { 4 } else { 1 })
        .sum()
}

/// The comments that end on the line above `line_start` (a byte offset at the start of a line).
/// A blank line or a line of code detaches the block. When `indent` is given, only comments at
/// that indentation count. Markers are removed; the text is otherwise preserved.
pub fn comments_above(source: &str, line_start: usize, indent: Option<usize>) -> String {
    let before = &source[..line_start.min(source.len())];
    let before = before.strip_suffix('\n').unwrap_or(before);
    // The lines above, nearest first, read from the end only as far as the comments go: splitting
    // the whole prefix would make each call cost the text before it (every completion item asks).
    let mut rest = (!before.is_empty()).then_some(before);
    let mut nearest: Vec<&str> = Vec::new();
    let width = indent_columns;
    let mut blocks: Vec<String> = Vec::new();
    // Lines already consumed from the end.
    let mut used = 0;
    loop {
        fill(&mut rest, &mut nearest, used);
        let Some(&raw) = nearest.get(used) else { break };
        let line = raw.trim_end_matches('\r');
        if indent.is_some_and(|want| width(line) != want) {
            break;
        }
        let text = line.trim();
        if text.starts_with("// ms:") {
            // A directive for the tools (`// ms: effect ...`), not documentation.
            used += 1;
        } else if let Some(comment) = text.strip_prefix("//") {
            blocks.push(
                comment
                    .strip_prefix(' ')
                    .unwrap_or(comment)
                    .trim_end()
                    .to_string(),
            );
            used += 1;
        } else if text.ends_with("*/") {
            // The block starts at the nearest line above that opens one.
            let mut open = used;
            let start = loop {
                fill(&mut rest, &mut nearest, open);
                let Some(candidate) = nearest.get(open) else {
                    break None;
                };
                if candidate.trim_start().starts_with("/*") {
                    break Some(open);
                }
                open += 1;
            };
            let Some(start) = start else { break };
            if indent.is_some_and(|want| width(nearest[start]) != want) {
                break;
            }
            let block: Vec<&str> = nearest[used..=start].iter().rev().copied().collect();
            blocks.push(block_text(&block));
            used = start + 1;
        } else {
            break;
        }
    }
    blocks.reverse();
    blocks.join("\n")
}

/// Reads lines from the end of `rest` into `nearest` until it holds line `upto` or the text ends.
fn fill<'a>(rest: &mut Option<&'a str>, nearest: &mut Vec<&'a str>, upto: usize) {
    while nearest.len() <= upto {
        let Some(text) = *rest else { break };
        match text.rsplit_once('\n') {
            Some((head, line)) => {
                nearest.push(line);
                *rest = Some(head);
            }
            None => {
                nearest.push(text);
                *rest = None;
            }
        }
    }
}

/// The text of a `/* */` block given as whole lines: markers removed, the common indentation of
/// the interior lines removed, and the blank lines next to the markers dropped.
fn block_text(lines: &[&str]) -> String {
    let first = lines[0].trim_start().strip_prefix("/*").unwrap_or("");
    let last = lines[lines.len() - 1].trim_end().trim_end_matches('\r');
    let last = last.strip_suffix("*/").unwrap_or(last);
    let mut rows: Vec<String> = Vec::new();
    if lines.len() == 1 {
        let one = first.strip_suffix("*/").unwrap_or(first);
        return one.trim().to_string();
    }
    rows.push(first.trim_end().to_string());
    rows.extend(
        lines[1..lines.len() - 1]
            .iter()
            .map(|l| l.trim_end().to_string()),
    );
    rows.push(last.trim_end().to_string());
    let common = rows[1..]
        .iter()
        .filter(|r| !r.trim().is_empty())
        .map(|r| r.len() - r.trim_start().len())
        .min()
        .unwrap_or(0);
    let mut rows: Vec<String> = rows
        .into_iter()
        .enumerate()
        .map(|(i, r)| {
            if i == 0 {
                r.trim_start().to_string()
            } else {
                r.get(common..).unwrap_or("").to_string()
            }
        })
        .collect();
    while rows.first().is_some_and(|r| r.trim().is_empty()) {
        rows.remove(0);
    }
    while rows.last().is_some_and(|r| r.trim().is_empty()) {
        rows.pop();
    }
    rows.join("\n")
}

/// The `//` comment that follows code on the line holding `offset`, without its marker. Text
/// literals on the line are skipped, so `"http://x"` is not a comment.
pub fn trailing_comment(source: &str, offset: usize) -> String {
    if offset > source.len() || !source.is_char_boundary(offset) {
        return String::new();
    }
    let start = source[..offset].rfind('\n').map_or(0, |n| n + 1);
    let line = source[start..]
        .split('\n')
        .next()
        .unwrap_or("")
        .trim_end_matches('\r');
    if !line.contains("//") {
        return String::new();
    }
    let bytes = line.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'"' => {
                let Some(end) = crate::lexer::quoted_text_end(&line[i..]) else {
                    return String::new();
                };
                i += end;
                continue;
            }
            b'/' if bytes.get(i + 1) == Some(&b'/') => {
                if i == 0 || line[..i].trim().is_empty() {
                    return String::new();
                }
                let rest = &line[i + 2..];
                return rest
                    .strip_prefix(' ')
                    .unwrap_or(rest)
                    .trim_end()
                    .to_string();
            }
            _ => {}
        }
        i += 1;
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn line_and_block_comments_above() {
        let src = "// one\n/*\n  two\n    three\n*/\nfn f()\n";
        let at = src.find("fn").unwrap();
        assert_eq!(comments_above(src, at, Some(0)), "one\ntwo\n  three");
    }

    #[test]
    fn blank_line_detaches() {
        let src = "// far\n\n// near\nfn f()\n";
        let at = src.find("fn").unwrap();
        assert_eq!(comments_above(src, at, Some(0)), "near");
    }

    #[test]
    fn crlf_directives_and_indentation_are_read_from_the_nearest_line() {
        let src = "// far\r\n\r\n  // ms: effect x\r\n  // near\r\n  fn f()\r\n";
        let at = src.find("  fn").unwrap();
        assert_eq!(comments_above(src, at, Some(2)), "near");
        assert_eq!(comments_above(src, at, Some(0)), "");
        let nested = "x\n  /* a\n     b */\n  fn f()\n";
        let at = nested.find("  fn").unwrap();
        assert_eq!(comments_above(nested, at, None), "a\nb");
        assert_eq!(comments_above("", 0, None), "");
        assert_eq!(comments_above("// only\n", 7, None), "only");
    }

    /// Reading the lines above used to split the whole text before the declaration, so asking
    /// for every item of a long file was quadratic.
    #[test]
    fn the_cost_of_a_lookup_does_not_grow_with_the_text_before_it() {
        let mut src = "fn f()\n".repeat(100_000);
        src.push_str("// doc\nfn g()\n");
        let at = src.find("fn g").unwrap();
        let start = std::time::Instant::now();
        for _ in 0..5_000 {
            assert_eq!(comments_above(&src, at, None), "doc");
        }
        assert!(start.elapsed().as_secs() < 3, "took {:?}", start.elapsed());
    }

    #[test]
    fn trailing() {
        let src = "    case A  // the first\n    x: String = \"http://a\"\n";
        assert_eq!(trailing_comment(src, 6), "the first");
        assert_eq!(trailing_comment(src, src.find("x:").unwrap()), "");
    }
}
