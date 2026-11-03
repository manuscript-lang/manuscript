//! Doc-comment extraction: the `//` lines and `/* */` blocks directly above a declaration, and a
//! trailing `//` on its line.

/// The comments that end on the line above `line_start` (a byte offset at the start of a line).
/// A blank line or a line of code detaches the block. When `indent` is given, only comments at
/// that indentation count. Markers are removed; the text is otherwise preserved.
pub fn comments_above(source: &str, line_start: usize, indent: Option<usize>) -> String {
    let before = &source[..line_start.min(source.len())];
    let before = before.strip_suffix('\n').unwrap_or(before);
    let lines: Vec<&str> = if before.is_empty() {
        Vec::new()
    } else {
        before.split('\n').collect()
    };
    let width = |s: &str| s.len() - s.trim_start_matches([' ', '\t']).len();
    let mut blocks: Vec<String> = Vec::new();
    let mut end = lines.len();
    while end > 0 {
        let line = lines[end - 1].trim_end_matches('\r');
        if indent.is_some_and(|want| width(line) != want) {
            break;
        }
        let text = line.trim();
        if let Some(rest) = text.strip_prefix("//") {
            blocks.push(
                rest.strip_prefix(' ')
                    .unwrap_or(rest)
                    .trim_end()
                    .to_string(),
            );
            end -= 1;
        } else if text.ends_with("*/") {
            let Some(start) = (0..end)
                .rev()
                .find(|&i| lines[i].trim_start().starts_with("/*"))
            else {
                break;
            };
            if indent.is_some_and(|want| width(lines[start]) != want) {
                break;
            }
            blocks.push(block_text(&lines[start..end]));
            end = start;
        } else {
            break;
        }
    }
    blocks.reverse();
    blocks.join("\n")
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
    let bytes = line.as_bytes();
    let (mut i, mut quoted) = (0, false);
    while i < bytes.len() {
        match bytes[i] {
            b'\\' if quoted => i += 1,
            b'"' => quoted = !quoted,
            b'/' if !quoted && bytes.get(i + 1) == Some(&b'/') => {
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
    fn trailing() {
        let src = "    case A  // the first\n    x: String = \"http://a\"\n";
        assert_eq!(trailing_comment(src, 6), "the first");
        assert_eq!(trailing_comment(src, src.find("x:").unwrap()), "");
    }
}
