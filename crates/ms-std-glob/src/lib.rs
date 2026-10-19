//! Glob syntax and matching, ported from `pkg/runtime/glob.go`.
//!
//! Callers own path normalisation and traversal. Braces expand before segmentation, `**` spans
//! segments, segments starting with `.` match only patterns that start with `.`, and `@( ) +( )
//! ?( ) *( ) !( )` are extended groups. Pure `no_std` with `alloc`; used by the path and
//! filesystem natives.
#![no_std]

extern crate alloc;

use alloc::collections::BTreeSet;
use alloc::string::String;
use alloc::vec::Vec;

#[derive(Debug, Clone)]
enum Atom {
    Star,
    Any,
    Class(Vec<ClassItem>, bool),
    Literal(char),
    /// `kind` is one of `@ + ? * !`.
    Group(u8, Vec<Vec<Atom>>),
}

#[derive(Debug, Clone)]
struct ClassItem {
    lo: char,
    hi: char,
}

/// Go's `path.Match` escape reader inside a bracket class: returns the character and the rest.
fn class_escape(chunk: &str) -> Option<(char, &str)> {
    let first = chunk.chars().next()?;
    if first == '-' || first == ']' {
        return None;
    }
    let chunk = if first == '\\' { &chunk[1..] } else { chunk };
    let c = chunk.chars().next()?;
    let rest = &chunk[c.len_utf8()..];
    if rest.is_empty() {
        return None;
    }
    Some((c, rest))
}

/// Parses `[...]` the way `path.Match` does (after the `[!` to `[^` rewrite); `None` is a bad pattern.
fn parse_class(token: &str) -> Option<Atom> {
    let mut chunk = &token[1..];
    if chunk.is_empty() {
        return None;
    }
    let negated = chunk.starts_with('^');
    if negated {
        chunk = &chunk[1..];
    }
    let mut items = Vec::new();
    loop {
        if chunk.starts_with(']') && !items.is_empty() {
            chunk = &chunk[1..];
            break;
        }
        let (lo, rest) = class_escape(chunk)?;
        chunk = rest;
        let mut hi = lo;
        if chunk.starts_with('-') {
            let (h, rest) = class_escape(&chunk[1..])?;
            hi = h;
            chunk = rest;
        }
        items.push(ClassItem { lo, hi });
    }
    if !chunk.is_empty() {
        return None;
    }
    Some(Atom::Class(items, negated))
}

fn sequence(pattern: &str) -> Option<Vec<Atom>> {
    let mut atoms = Vec::new();
    let mut p = pattern;
    while let Some(ch) = p.chars().next() {
        let bytes = p.as_bytes();
        if matches!(ch, '@' | '+' | '?' | '!' | '*') && bytes.len() > 1 && bytes[1] == b'(' {
            let start = 2;
            let mut depth = 1;
            let mut end = start;
            while end < bytes.len() && depth > 0 {
                if bytes[end] == b'(' {
                    depth += 1;
                }
                if bytes[end] == b')' {
                    depth -= 1;
                }
                if depth > 0 {
                    end += 1;
                }
            }
            if depth != 0 {
                return None;
            }
            let inside = &p[start..end];
            let mut parts: Vec<&str> = Vec::new();
            let (mut at, mut nested) = (0, 0i32);
            for (i, &b) in inside.as_bytes().iter().enumerate() {
                match b {
                    b'(' => nested += 1,
                    b')' => nested -= 1,
                    b'|' if nested == 0 => {
                        parts.push(&inside[at..i]);
                        at = i + 1;
                    }
                    _ => {}
                }
            }
            parts.push(&inside[at..]);
            let mut alternatives = Vec::new();
            for part in parts {
                alternatives.push(sequence(part)?);
            }
            atoms.push(Atom::Group(ch as u8, alternatives));
            p = &p[end + 1..];
            continue;
        }
        match ch {
            '*' => {
                atoms.push(Atom::Star);
                p = &p[1..];
            }
            '?' => {
                atoms.push(Atom::Any);
                p = &p[1..];
            }
            '[' => {
                let end = p.find(']')?;
                let token = &p[..=end];
                let rewritten;
                let token = if let Some(rest) = token.strip_prefix("[!") {
                    rewritten = alloc::format!("[^{rest}");
                    rewritten.as_str()
                } else {
                    token
                };
                atoms.push(parse_class(token)?);
                p = &p[end + 1..];
            }
            '\\' => {
                let rest = &p[1..];
                let c = rest.chars().next()?;
                atoms.push(Atom::Literal(c));
                p = &rest[c.len_utf8()..];
            }
            c => {
                atoms.push(Atom::Literal(c));
                p = &p[c.len_utf8()..];
            }
        }
    }
    Some(atoms)
}

fn ends(atoms: &[Atom], value: &[char], start: usize) -> BTreeSet<usize> {
    let mut positions: BTreeSet<usize> = BTreeSet::new();
    positions.insert(start);
    for atom in atoms {
        let mut next: BTreeSet<usize> = BTreeSet::new();
        if let Atom::Star = atom {
            // A star reaches every position from the earliest start onward.
            let earliest = positions.iter().next().copied().unwrap_or(value.len() + 1);
            for i in earliest..=value.len() {
                next.insert(i);
            }
            positions = next;
            if positions.is_empty() {
                break;
            }
            continue;
        }
        for &at in &positions {
            match atom {
                Atom::Star => {}
                Atom::Literal(c) => {
                    if at < value.len() && value[at] == *c {
                        next.insert(at + 1);
                    }
                }
                Atom::Any => {
                    if at < value.len() {
                        next.insert(at + 1);
                    }
                }
                Atom::Class(items, negated) => {
                    if at < value.len() {
                        let r = value[at];
                        let hit = items.iter().any(|i| i.lo <= r && r <= i.hi);
                        if hit != *negated {
                            next.insert(at + 1);
                        }
                    }
                }
                Atom::Group(kind, alternatives) => {
                    let mut accepted: BTreeSet<usize> = BTreeSet::new();
                    for alternative in alternatives {
                        accepted.extend(ends(alternative, value, at));
                    }
                    if *kind == b'!' {
                        for end in at..=value.len() {
                            if !accepted.contains(&end) {
                                next.insert(end);
                            }
                        }
                        continue;
                    }
                    next.extend(accepted.iter().copied());
                    if *kind == b'?' || *kind == b'*' {
                        next.insert(at);
                    }
                    if *kind == b'+' || *kind == b'*' {
                        let mut queue: Vec<usize> = Vec::new();
                        let mut seen: BTreeSet<usize> = BTreeSet::new();
                        seen.insert(at);
                        for &end in &accepted {
                            if seen.insert(end) {
                                queue.push(end);
                            }
                        }
                        let mut head = 0;
                        while head < queue.len() {
                            let position = queue[head];
                            head += 1;
                            for alternative in alternatives {
                                for end in ends(alternative, value, position) {
                                    next.insert(end);
                                    if seen.insert(end) {
                                        queue.push(end);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        positions = next;
        if positions.is_empty() {
            break;
        }
    }
    positions
}

#[derive(Debug, Clone)]
struct Segment {
    pattern: String,
    /// `None` for `**`.
    atoms: Option<Vec<Atom>>,
}

fn segments(pattern: &str) -> Option<Vec<Segment>> {
    pattern
        .split('/')
        .map(|part| {
            let atoms = if part == "**" {
                None
            } else {
                Some(sequence(part)?)
            };
            Some(Segment {
                pattern: String::from(part),
                atoms,
            })
        })
        .collect()
}

fn match_segments(value: &[&str], pattern: &[Segment]) -> bool {
    let n = value.len();
    let mut previous = alloc::vec![false; n + 1];
    previous[0] = true;
    for segment in pattern {
        let mut next = alloc::vec![false; n + 1];
        match &segment.atoms {
            None => {
                next[0] = previous[0];
                for j in 1..=n {
                    next[j] = previous[j] || (next[j - 1] && !value[j - 1].starts_with('.'));
                }
            }
            Some(atoms) => {
                for j in 1..=n {
                    if previous[j - 1]
                        && (!value[j - 1].starts_with('.') || segment.pattern.starts_with('.'))
                    {
                        let runes: Vec<char> = value[j - 1].chars().collect();
                        next[j] = ends(atoms, &runes, 0).contains(&runes.len());
                    }
                }
            }
        }
        previous = next;
    }
    previous[n]
}

fn brace_letter(c: u8) -> bool {
    c.is_ascii_alphabetic()
}

fn parse_int(s: &str) -> Option<i64> {
    // Go's `strconv.Atoi`: optional sign, decimal digits only.
    let digits = s.strip_prefix(['+', '-']).unwrap_or(s);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse::<i64>().ok()
}

/// Brace expansion runs before segmentation, so alternatives may cross directory boundaries.
fn expand_braces(pattern: &str) -> Option<Vec<String>> {
    let bytes = pattern.as_bytes();
    let mut open = None;
    let (mut escaped, mut bracket) = (false, false);
    for (i, &ch) in bytes.iter().enumerate() {
        if escaped {
            escaped = false;
            continue;
        }
        if ch == b'\\' {
            escaped = true;
            continue;
        }
        if ch == b'[' {
            bracket = true;
        }
        if ch == b']' {
            bracket = false;
        }
        if ch == b'{' && !bracket {
            open = Some(i);
            break;
        }
    }
    let Some(open) = open else {
        return Some(alloc::vec![String::from(pattern)]);
    };
    let mut depth = 1;
    let mut end = open + 1;
    while end < bytes.len() && depth > 0 {
        if bytes[end] == b'{' {
            depth += 1;
        }
        if bytes[end] == b'}' {
            depth -= 1;
        }
        if depth > 0 {
            end += 1;
        }
    }
    if depth != 0 {
        return None;
    }
    let inside = &pattern[open + 1..end];
    let mut parts: Vec<String> = Vec::new();
    let (mut at, mut nested) = (0, 0i32);
    for (i, &b) in inside.as_bytes().iter().enumerate() {
        if b == b'{' {
            nested += 1;
        }
        if b == b'}' {
            nested -= 1;
        }
        if b == b',' && nested == 0 {
            parts.push(String::from(&inside[at..i]));
            at = i + 1;
        }
    }
    parts.push(String::from(&inside[at..]));
    if parts.len() == 1 {
        let fields: Vec<&str> = inside.split("..").collect();
        if fields.len() == 1 {
            let mut tails = expand_braces(&pattern[end + 1..])?;
            for t in &mut tails {
                *t = alloc::format!("{}{}", &pattern[..end + 1], t);
            }
            return Some(tails);
        }
        if fields.len() > 3 {
            return None;
        }
        let mut step: i64 = 1;
        if fields.len() == 3 {
            let n = parse_int(fields[2])?;
            if n == 0 {
                return None;
            }
            step = n.abs();
        }
        let (e1, e2) = (parse_int(fields[0]), parse_int(fields[1]));
        let (mut lo, mut hi, mut alpha) = (e1.unwrap_or(0), e2.unwrap_or(0), false);
        if e1.is_none() || e2.is_none() {
            let (a, b) = (fields[0].as_bytes(), fields[1].as_bytes());
            if a.len() != 1 || b.len() != 1 || !brace_letter(a[0]) || !brace_letter(b[0]) {
                return None;
            }
            lo = a[0] as i64;
            hi = b[0] as i64;
            alpha = true;
        }
        if !(-100_000..=100_000).contains(&lo)
            || !(-100_000..=100_000).contains(&hi)
            || (lo - hi).abs() / step > 1024
        {
            return None;
        }
        let mut width = 0;
        for endpoint in &fields[..2] {
            let unsigned = endpoint.strip_prefix('-').unwrap_or(endpoint);
            if unsigned.len() > 1 && unsigned.starts_with('0') {
                width = width.max(unsigned.len());
            }
        }
        if lo > hi {
            step = -step;
        }
        parts.clear();
        let mut n = lo;
        while (step > 0 && n <= hi) || (step < 0 && n >= hi) {
            let value = if alpha {
                String::from(char::from_u32(n as u32).unwrap_or('\u{fffd}'))
            } else if width > 0 {
                let unsigned = alloc::format!("{}", n.abs());
                let mut v = String::new();
                if n < 0 {
                    v.push('-');
                }
                for _ in unsigned.len()..width {
                    v.push('0');
                }
                v.push_str(&unsigned);
                v
            } else {
                alloc::format!("{n}")
            };
            parts.push(value);
            n += step;
        }
    }
    let mut result: Vec<String> = Vec::new();
    for part in parts {
        let joined = alloc::format!("{}{}{}", &pattern[..open], part, &pattern[end + 1..]);
        let expanded = expand_braces(&joined)?;
        if result.len() + expanded.len() > 1025 {
            return None;
        }
        result.extend(expanded);
    }
    Some(result)
}

/// A parsed glob, reusable for every entry of one query.
#[derive(Debug, Clone)]
pub struct Glob {
    alternatives: Vec<Vec<Segment>>,
}

impl Glob {
    /// `None` for a malformed pattern, one over 4096 bytes, or one holding NUL.
    pub fn parse(pattern: &str) -> Option<Glob> {
        if pattern.len() > 4096 || pattern.contains('\0') {
            return None;
        }
        let mut alternatives = Vec::new();
        for alternative in expand_braces(pattern)? {
            alternatives.push(segments(&alternative)?);
        }
        Some(Glob { alternatives })
    }

    /// Tests a slash-separated path.
    pub fn matches(&self, value: &str) -> bool {
        let parts: Vec<&str> = value.split('/').collect();
        self.alternatives.iter().any(|a| match_segments(&parts, a))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn m(pattern: &str, value: &str) -> bool {
        Glob::parse(pattern)
            .unwrap_or_else(|| panic!("{pattern:?} should parse"))
            .matches(value)
    }

    #[test]
    fn wildcards_and_dotfiles() {
        assert!(m("*.ms", "a.ms"));
        assert!(!m("*.ms", "dir/a.ms"));
        assert!(m("**/*.ms", "dir/sub/a.ms"));
        assert!(m("**/*.ms", "a.ms"));
        assert!(!m("*", ".hidden"));
        assert!(m(".*", ".hidden"));
        assert!(!m("**/a", ".d/a"));
        assert!(m("a?c", "abc"));
        assert!(m("[a-c]x", "bx"));
        assert!(m("[!a-c]x", "dx"));
        assert!(!m("[!a-c]x", "bx"));
        assert!(m("a\\*b", "a*b"));
        assert!(!m("a\\*b", "axb"));
    }

    #[test]
    fn extended_groups_and_braces() {
        assert!(m("@(foo|bar).ms", "bar.ms"));
        assert!(m("+(ab)c", "ababc"));
        assert!(m("?(x)y", "y"));
        assert!(m("*(ab)c", "c"));
        assert!(m("!(a)b", "xb"));
        assert!(m("{a,b}/c", "b/c"));
        assert!(m("f{1..3}", "f2"));
        assert!(!m("f{1..3}", "f4"));
        assert!(m("f{01..03}", "f02"));
        assert!(m("{a..c}", "b"));
        assert!(m("f{1..5..2}", "f3"));
        assert!(!m("f{1..5..2}", "f2"));
    }

    #[test]
    fn rejects_malformed_patterns() {
        for bad in [
            "[",
            "[]",
            "[a-",
            "a\\",
            "@(a",
            "{a",
            "{1..x}",
            "{1..2..0}",
            "[a-]",
        ] {
            assert!(Glob::parse(bad).is_none(), "{bad:?}");
        }
        assert!(Glob::parse(&"a".repeat(4097)).is_none());
        assert!(Glob::parse("a\0b").is_none());
    }
}
