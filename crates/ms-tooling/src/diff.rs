//! Unified diff parsing and reverse application. Never runs git.

use std::borrow::Cow;

/// One `@@` hunk. Lines keep their one-character prefix: ' ' context, '+'
/// added, '-' removed.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DiffHunk {
    pub old_start: i64,
    pub old_len: i64,
    pub new_start: i64,
    pub new_len: i64,
    pub lines: Vec<String>,
    /// The final old-side line has no line terminator.
    pub old_no_newline: bool,
    /// The final new-side line has no line terminator.
    pub new_no_newline: bool,
}

/// The hunks for one file. An empty `old` marks an added file and an empty
/// `new` a deleted one.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DiffFile {
    pub old: String,
    pub new: String,
    pub hunks: Vec<DiffHunk>,
}

impl DiffFile {
    pub fn path(&self) -> &str {
        if self.new.is_empty() {
            &self.old
        } else {
            &self.new
        }
    }

    /// Head-side line numbers the hunks changed. A removal is attributed to
    /// the head line that follows it.
    pub fn touched_lines(&self) -> Vec<i64> {
        let mut touched = Vec::new();
        for hunk in &self.hunks {
            let mut line = hunk.new_start;
            if hunk.new_len == 0 {
                line += 1;
            }
            for text in &hunk.lines {
                let first = text.as_bytes()[0];
                if first == b'+' || first == b'-' {
                    touched.push(line);
                }
                if first != b'-' {
                    line += 1;
                }
            }
        }
        touched
    }
}

const RENAME_HINT: &str =
    "renamed files are not supported; produce the diff with git diff --no-renames";

/// Reads a unified diff (git or plain `diff -u`).
pub fn parse_diff(text: &str) -> Result<Vec<DiffFile>, String> {
    let text = text.replace("\r\n", "\n");
    // A final terminator ends the preceding line; it is not an extra blank
    // context line that can satisfy a truncated hunk's declared length.
    let lines: Vec<&str> = text.split_terminator('\n').collect();
    let mut files: Vec<DiffFile> = Vec::new();
    let mut have_current = false;
    let mut git = false;
    let mut git_header = None;
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        if let Some(fields) = line.strip_prefix("diff --git ") {
            git_header = Some(fields);
            files.push(DiffFile::default());
            have_current = true;
            git = true;
        } else if line.starts_with("rename from ") || line.starts_with("rename to ") {
            return Err(RENAME_HINT.to_string());
        } else if line.starts_with("--- ")
            && i + 1 < lines.len()
            && lines[i + 1].starts_with("+++ ")
        {
            if !have_current || !git {
                files.push(DiffFile::default());
                have_current = true;
            }
            let current = files.last_mut().expect("a file was just pushed");
            current.old = diff_path(&line[4..], "a/", git)
                .map_err(|e| format!("diff line {}: {e}", i + 1))?;
            current.new = diff_path(&lines[i + 1][4..], "b/", git)
                .map_err(|e| format!("diff line {}: {e}", i + 2))?;
            if !git
                && current.old.starts_with("a/")
                && current.new.starts_with("b/")
                && current.old[2..] == current.new[2..]
            {
                current.old = current.old[2..].to_string();
                current.new = current.new[2..].to_string();
            }
            i += 1;
        } else if line.starts_with("@@ ") {
            if !have_current {
                return Err(format!("diff line {}: hunk before any file header", i + 1));
            }
            let (hunk, next) = parse_hunk(&lines, i)?;
            files.last_mut().expect("have_current").hunks.push(hunk);
            i = next;
            continue;
        } else if matches!(
            line.as_bytes().first(),
            Some(b'o' | b'n' | b'd' | b'B' | b'G')
        ) && git
            && have_current
            && (line.starts_with("old mode ")
                || line.starts_with("new mode ")
                || line.starts_with("new file mode ")
                || line.starts_with("deleted file mode ")
                || line.starts_with("Binary files ")
                || line == "GIT binary patch")
        {
            if line.starts_with("Binary files ") || line == "GIT binary patch" {
                return Err("binary diff cannot reconstruct the base; produce a text diff with git diff --text --no-renames".to_string());
            }
            let current = files.last_mut().expect("have_current");
            if current.old.is_empty()
                && current.new.is_empty()
                && let Some(path) = git_header.take().and_then(git_section_path)
            {
                current.old = path.clone();
                current.new = path;
            }
            if line.starts_with("new file mode ") {
                current.old.clear();
            } else if line.starts_with("deleted file mode ") {
                current.new.clear();
            }
        }
        i += 1;
    }
    if files.is_empty() && !text.trim().is_empty() {
        return Err("input is not a unified diff; pipe in git diff --no-renames".to_string());
    }
    for file in &files {
        if file.old.is_empty() && file.new.is_empty() {
            return Err("diff has a file header with no paths".to_string());
        }
        if !file.old.is_empty() && !file.new.is_empty() && file.old != file.new {
            return Err(format!(
                "renamed files are not supported ({} -> {}); produce the diff with git diff --no-renames",
                file.old, file.new
            ));
        }
    }
    Ok(files)
}

// A non-renamed Git section repeats the same path with a/ and b/ prefixes.
// Those encoded fields have equal byte lengths, even when spaces are unquoted
// or unusual bytes are quoted. Text headers, when present, remain authoritative.
fn git_section_path(fields: &str) -> Option<String> {
    let (old, new) = fields.split_at_checked(fields.len() / 2)?;
    let new = new.strip_prefix(' ')?;
    let old = diff_path(old, "a/", true).ok()?;
    let new = diff_path(new, "b/", true).ok()?;
    (old == new).then_some(old)
}

fn diff_path(field: &str, prefix: &str, git: bool) -> Result<String, String> {
    let path = field.split('\t').next().unwrap_or("");
    // Git leaves spaces unquoted and uses a tab to delimit such path headers.
    let path = if git { path } else { path.trim() };
    if path == "/dev/null" {
        return Ok(String::new());
    }
    if git {
        let path = if path.starts_with('"') {
            Cow::Owned(git_quoted_path(path)?)
        } else {
            Cow::Borrowed(path)
        };
        return Ok(path.strip_prefix(prefix).unwrap_or(&path).to_string());
    }
    Ok(path.to_string())
}

/// Git quotes unusual path bytes, including UTF-8 bytes as three octal digits.
/// Decode bytes first: decoding individual octal escapes as Unicode corrupts names.
fn git_quoted_path(path: &str) -> Result<String, String> {
    let malformed = || "malformed Git quoted path".to_string();
    let body = path
        .strip_prefix('"')
        .and_then(|s| s.strip_suffix('"'))
        .ok_or_else(malformed)?;
    let mut input = body.bytes();
    let mut bytes = Vec::with_capacity(body.len());
    while let Some(byte) = input.next() {
        if byte == b'"' {
            return Err(malformed());
        }
        if byte != b'\\' {
            bytes.push(byte);
            continue;
        }
        let escaped = input.next().ok_or_else(malformed)?;
        let value = match escaped {
            b'"' | b'\\' => escaped,
            b'a' => 7,
            b'b' => 8,
            b't' => b'\t',
            b'n' => b'\n',
            b'v' => 11,
            b'f' => 12,
            b'r' => b'\r',
            b'0'..=b'3' => {
                let second = input
                    .next()
                    .filter(|b| (b'0'..=b'7').contains(b))
                    .ok_or_else(malformed)?;
                let third = input
                    .next()
                    .filter(|b| (b'0'..=b'7').contains(b))
                    .ok_or_else(malformed)?;
                (escaped - b'0') * 64 + (second - b'0') * 8 + (third - b'0')
            }
            _ => return Err(malformed()),
        };
        bytes.push(value);
    }
    if bytes.contains(&0) {
        return Err("Git path contains a NUL byte".to_string());
    }
    String::from_utf8(bytes).map_err(|_| "Git path is not valid UTF-8".to_string())
}

fn parse_hunk(lines: &[&str], start: usize) -> Result<(DiffHunk, usize), String> {
    let malformed = || format!("diff line {}: malformed hunk header", start + 1);
    let header = lines[start];
    let rest = &header[3..];
    let end = rest.find(" @@").ok_or_else(malformed)?;
    let (old, new) = rest[..end].split_once(' ').ok_or_else(malformed)?;
    if !old.starts_with('-') || !new.starts_with('+') {
        return Err(malformed());
    }
    let mut h = DiffHunk::default();
    let parsed = parse_range(&old[1..]).and_then(|o| parse_range(&new[1..]).map(|n| (o, n)));
    let ((os, ol), (ns, nl)) = parsed.map_err(|e| format!("diff line {}: {e}", start + 1))?;
    (h.old_start, h.old_len, h.new_start, h.new_len) = (os, ol, ns, nl);
    let (mut old_left, mut new_left) = (h.old_len, h.new_len);
    let mut i = start + 1;
    while i < lines.len() && (old_left > 0 || new_left > 0) {
        let mut line = lines[i];
        if line.starts_with('\\') {
            record_no_newline(&mut h);
            i += 1;
            continue;
        }
        if line.is_empty() {
            line = " ";
        }
        match line.as_bytes()[0] {
            b' ' => {
                old_left -= 1;
                new_left -= 1;
            }
            b'-' => old_left -= 1,
            b'+' => new_left -= 1,
            _ => {
                return Err(format!(
                    "diff line {}: hunk ends before its declared length",
                    i + 1
                ));
            }
        }
        h.lines.push(line.to_string());
        i += 1;
    }
    if old_left != 0 || new_left != 0 {
        return Err(format!(
            "diff line {}: hunk is shorter than its header declares",
            start + 1
        ));
    }
    while i < lines.len() && lines[i].starts_with('\\') {
        record_no_newline(&mut h);
        i += 1;
    }
    Ok((h, i))
}

// The no-newline note can be localized by the diff producer; its leading
// backslash and the preceding side marker carry the structural meaning.
fn record_no_newline(hunk: &mut DiffHunk) {
    if let Some(line) = hunk.lines.last() {
        hunk.old_no_newline |= !line.starts_with('+');
        hunk.new_no_newline |= !line.starts_with('-');
    }
}

fn parse_range(text: &str) -> Result<(i64, i64), String> {
    let malformed = || format!("malformed hunk range {text:?}");
    let (first, second) = match text.split_once(',') {
        Some((a, b)) => (a, Some(b)),
        None => (text, None),
    };
    let unsigned = |value: &str| !value.is_empty() && value.bytes().all(|b| b.is_ascii_digit());
    if !unsigned(first) || second.is_some_and(|value| !unsigned(value)) {
        return Err(malformed());
    }
    let start: i64 = first.parse().map_err(|_| malformed())?;
    let length: i64 = match second {
        Some(s) => s.parse().map_err(|_| malformed())?,
        None => 1,
    };
    // Nonempty ranges start at one; traversal also needs the exclusive end,
    // or the following line for a zero-length deletion/insertion anchor.
    if (start == 0 && length != 0) || start.checked_add(length.max(1)).is_none() {
        return Err(malformed());
    }
    Ok((start, length))
}

/// Reconstructs the base file from the head file and the hunks. Every context
/// and added line is checked against the head, so a diff that does not
/// describe this tree is an error rather than a guess.
pub fn reverse_apply(head: &str, hunks: &[DiffHunk]) -> Result<String, String> {
    let source: Vec<&str> = head.split_terminator('\n').collect();
    let mut trailing_newline = head.ends_with('\n');
    let mut out: Vec<&str> = Vec::new();
    let mut position = 0usize;
    let same = |a: &str, b: &str| a.trim_end_matches('\r') == b.trim_end_matches('\r');
    for hunk in hunks {
        let mut index = hunk.new_start - 1;
        if hunk.new_len == 0 {
            index = hunk.new_start;
        }
        if index < position as i64 || index > source.len() as i64 {
            return Err(format!(
                "hunks overlap or fall outside the file at line {}",
                hunk.new_start
            ));
        }
        let mut index = index as usize;
        out.extend_from_slice(&source[position..index]);
        for line in &hunk.lines {
            let text = &line[1..];
            if line.as_bytes()[0] == b'-' {
                out.push(text);
                continue;
            }
            if index >= source.len() || !same(source[index], text) {
                return Err(format!("line {} does not match the diff", index + 1));
            }
            if line.as_bytes()[0] == b' ' {
                out.push(source[index]);
            }
            index += 1;
        }
        if hunk.new_no_newline && index != source.len() {
            return Err("no-newline marker appears before the end of the file".to_string());
        }
        if index == source.len() {
            if hunk.new_len > 0 && hunk.new_no_newline == head.ends_with('\n') {
                return Err("final newline does not match the diff".to_string());
            }
            trailing_newline = !hunk.old_no_newline;
        }
        position = index;
    }
    out.extend_from_slice(&source[position..]);
    let mut result = out.join("\n");
    if !out.is_empty() && trailing_newline {
        result.push('\n');
    }
    Ok(result)
}

/// The base text of a deleted file.
pub fn removed_content(hunks: &[DiffHunk]) -> String {
    let mut out: Vec<&str> = Vec::new();
    for hunk in hunks {
        for line in &hunk.lines {
            if line.as_bytes()[0] == b'-' {
                out.push(&line[1..]);
            }
        }
    }
    let mut result = out.join("\n");
    if !out.is_empty() && !hunks.last().is_some_and(|h| h.old_no_newline) {
        result.push('\n');
    }
    result
}
