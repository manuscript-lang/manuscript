//! Unified diff parsing and reverse application. Never runs git.

/// One `@@` hunk. Lines keep their one-character prefix: ' ' context, '+'
/// added, '-' removed.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct DiffHunk {
    pub old_start: i64,
    pub old_len: i64,
    pub new_start: i64,
    pub new_len: i64,
    pub lines: Vec<String>,
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
    let lines: Vec<&str> = text.split('\n').collect();
    let mut files: Vec<DiffFile> = Vec::new();
    let mut have_current = false;
    let mut git = false;
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        if line.starts_with("diff --git ") {
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
            current.old = diff_path(&line[4..], "a/", git);
            current.new = diff_path(&lines[i + 1][4..], "b/", git);
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

fn diff_path(field: &str, prefix: &str, git: bool) -> String {
    let path = field.split('\t').next().unwrap_or("").trim();
    if path == "/dev/null" {
        return String::new();
    }
    if git {
        return path.strip_prefix(prefix).unwrap_or(path).to_string();
    }
    path.to_string()
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
        i += 1;
    }
    Ok((h, i))
}

fn parse_range(text: &str) -> Result<(i64, i64), String> {
    let malformed = || format!("malformed hunk range {text:?}");
    let (first, second) = match text.split_once(',') {
        Some((a, b)) => (a, Some(b)),
        None => (text, None),
    };
    let start = atoi(first).ok_or_else(malformed)?;
    let length = match second {
        Some(s) => atoi(s).ok_or_else(malformed)?,
        None => 1,
    };
    Ok((start, length))
}

/// Go's `strconv.Atoi`: optional sign, then ASCII digits only.
pub(crate) fn atoi(text: &str) -> Option<i64> {
    let digits = text.strip_prefix(['+', '-']).unwrap_or(text);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    text.parse().ok()
}

/// Reconstructs the base file from the head file and the hunks. Every context
/// and added line is checked against the head, so a diff that does not
/// describe this tree is an error rather than a guess.
pub fn reverse_apply(head: &str, hunks: &[DiffHunk]) -> Result<String, String> {
    let source: Vec<&str> = head.split('\n').collect();
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
        position = index;
    }
    out.extend_from_slice(&source[position..]);
    Ok(out.join("\n"))
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
    out.join("\n") + "\n"
}
