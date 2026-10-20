//! Glob syntax and matching. Shared by path predicates and
//! filesystem queries): `*`, `?`, `[...]` classes, extended `@(..) +(..) ?(..) !(..) *(..)`
//! groups, `{a,b}` and `{1..3}` brace expansion, and `**` segments.

use alloc::string::{String, ToString};
use alloc::vec;
use alloc::vec::Vec;

enum Atom {
    Star,
    Any,
    Class(Class),
    Literal(char),
    Group(char, Vec<Vec<Atom>>),
}

struct Class {
    negated: bool,
    ranges: Vec<(char, char)>,
}

impl Class {
    fn matches(&self, c: char) -> bool {
        self.ranges.iter().any(|&(lo, hi)| lo <= c && c <= hi) != self.negated
    }
}

/// One escaped-or-plain class member (Go's `path.getEsc`).
fn class_member(chunk: &str) -> Option<(char, &str)> {
    let mut rest = chunk;
    match rest.chars().next() {
        None | Some('-') | Some(']') => return None,
        Some('\\') => {
            rest = &rest[1..];
            rest.chars().next()?;
        }
        _ => {}
    }
    let c = rest.chars().next()?;
    let tail = &rest[c.len_utf8()..];
    if tail.is_empty() {
        return None;
    }
    Some((c, tail))
}

/// Parses a `[...]` token as Go's `path.Match` does; `None` is `ErrBadPattern`.
fn parse_class(token: &str) -> Option<Class> {
    let mut chunk = &token[1..];
    let negated = chunk.starts_with('^');
    if negated {
        chunk = &chunk[1..];
    }
    let mut ranges = Vec::new();
    loop {
        if chunk.starts_with(']') && !ranges.is_empty() {
            break;
        }
        let (lo, rest) = class_member(chunk)?;
        chunk = rest;
        let mut hi = lo;
        if chunk.starts_with('-') {
            let (h, rest) = class_member(&chunk[1..])?;
            hi = h;
            chunk = rest;
        }
        ranges.push((lo, hi));
    }
    Some(Class { negated, ranges })
}

fn sequence(mut pattern: &str) -> Option<Vec<Atom>> {
    let mut atoms = Vec::new();
    while let Some(ch) = pattern.chars().next() {
        if "@+?!*".contains(ch) && pattern.len() > 1 && pattern.as_bytes()[1] == b'(' {
            let b = pattern.as_bytes();
            let start = 2;
            let mut depth = 1;
            let mut end = start;
            while end < b.len() && depth > 0 {
                if b[end] == b'(' {
                    depth += 1;
                }
                if b[end] == b')' {
                    depth -= 1;
                }
                if depth > 0 {
                    end += 1;
                }
            }
            if depth != 0 {
                return None;
            }
            let inside = &pattern[start..end];
            let mut parts = Vec::new();
            let (mut at, mut nested) = (0, 0i32);
            for (i, &c) in inside.as_bytes().iter().enumerate() {
                match c {
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
            let alternatives = parts
                .into_iter()
                .map(sequence)
                .collect::<Option<Vec<_>>>()?;
            atoms.push(Atom::Group(ch, alternatives));
            pattern = &pattern[end + 1..];
            continue;
        }
        match ch {
            '*' => {
                atoms.push(Atom::Star);
                pattern = &pattern[1..];
            }
            '?' => {
                atoms.push(Atom::Any);
                pattern = &pattern[1..];
            }
            '[' => {
                let end = pattern.find(']')?;
                let mut token = pattern[..=end].to_string();
                if token.starts_with("[!") {
                    token = String::from("[^") + &token[2..];
                }
                atoms.push(Atom::Class(parse_class(&token)?));
                pattern = &pattern[end + 1..];
            }
            '\\' => {
                let c = pattern[1..].chars().next()?;
                atoms.push(Atom::Literal(c));
                pattern = &pattern[1 + c.len_utf8()..];
            }
            c => {
                atoms.push(Atom::Literal(c));
                pattern = &pattern[c.len_utf8()..];
            }
        }
    }
    Some(atoms)
}

/// Positions reachable after matching `atoms` from `start`.
fn ends(atoms: &[Atom], value: &[char], start: usize) -> Vec<bool> {
    let n = value.len();
    let mut positions = vec![false; n + 1];
    positions[start] = true;
    for atom in atoms {
        let mut next = vec![false; n + 1];
        match atom {
            Atom::Star => {
                if let Some(earliest) = positions.iter().position(|&p| p) {
                    next[earliest..].fill(true);
                }
            }
            Atom::Literal(c) => {
                for at in (0..n).filter(|&at| positions[at]) {
                    if value[at] == *c {
                        next[at + 1] = true;
                    }
                }
            }
            Atom::Any => {
                for at in (0..n).filter(|&at| positions[at]) {
                    next[at + 1] = true;
                }
            }
            Atom::Class(class) => {
                for at in (0..n).filter(|&at| positions[at]) {
                    if class.matches(value[at]) {
                        next[at + 1] = true;
                    }
                }
            }
            Atom::Group(kind, alternatives) => {
                for at in (0..=n).filter(|&at| positions[at]) {
                    let mut accepted = vec![false; n + 1];
                    for alt in alternatives {
                        for (e, ok) in ends(alt, value, at).into_iter().enumerate() {
                            accepted[e] |= ok;
                        }
                    }
                    if *kind == '!' {
                        for e in at..=n {
                            if !accepted[e] {
                                next[e] = true;
                            }
                        }
                        continue;
                    }
                    for (e, &ok) in accepted.iter().enumerate() {
                        if ok {
                            next[e] = true;
                        }
                    }
                    if *kind == '?' || *kind == '*' {
                        next[at] = true;
                    }
                    if *kind == '+' || *kind == '*' {
                        let mut seen = vec![false; n + 1];
                        seen[at] = true;
                        let mut queue = alloc::collections::VecDeque::new();
                        for (e, &ok) in accepted.iter().enumerate() {
                            if ok && !seen[e] {
                                seen[e] = true;
                                queue.push_back(e);
                            }
                        }
                        while let Some(position) = queue.pop_front() {
                            for alt in alternatives {
                                for (e, ok) in ends(alt, value, position).into_iter().enumerate() {
                                    if ok {
                                        next[e] = true;
                                        if !seen[e] {
                                            seen[e] = true;
                                            queue.push_back(e);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        positions = next;
        if !positions.iter().any(|&p| p) {
            break;
        }
    }
    positions
}

struct Segment {
    pattern: String,
    atoms: Vec<Atom>,
}

/// A compiled glob, reusable across values.
pub struct Glob(Vec<Vec<Segment>>);

fn parse_segments(pattern: &str) -> Option<Vec<Segment>> {
    pattern
        .split('/')
        .map(|part| {
            let atoms = if part == "**" {
                Vec::new()
            } else {
                sequence(part)?
            };
            Some(Segment {
                pattern: part.to_string(),
                atoms,
            })
        })
        .collect()
}

impl Glob {
    /// Compiles `pattern` (longer than 4096 bytes, NUL bytes, bad syntax: `None`).
    pub fn new(pattern: &str) -> Option<Glob> {
        if pattern.len() > 4096 || pattern.contains('\0') {
            return None;
        }
        let compiled = expand_braces(pattern)?
            .iter()
            .map(|alt| parse_segments(alt))
            .collect::<Option<Vec<_>>>()?;
        Some(Glob(compiled))
    }

    /// Whether `value` (slash separated) matches.
    pub fn matches(&self, value: &str) -> bool {
        let parts: Vec<&str> = value.split('/').collect();
        self.0.iter().any(|alt| match_segments(&parts, alt))
    }
}

/// Matching without up-front validation: a matching earlier alternative still succeeds even if
/// a later one is malformed.
pub fn matches_lenient(value: &str, pattern: &str) -> bool {
    let Some(patterns) = expand_braces(pattern) else {
        return false;
    };
    let parts: Vec<&str> = value.split('/').collect();
    patterns
        .iter()
        .any(|alt| parse_segments(alt).is_some_and(|segments| match_segments(&parts, &segments)))
}

fn match_segments(value: &[&str], pattern: &[Segment]) -> bool {
    let n = value.len();
    let mut previous = vec![false; n + 1];
    previous[0] = true;
    for segment in pattern {
        let mut next = vec![false; n + 1];
        if segment.pattern == "**" {
            next[0] = previous[0];
            for j in 1..=n {
                next[j] = previous[j] || next[j - 1] && !value[j - 1].starts_with('.');
            }
        } else {
            for j in 1..=n {
                if previous[j - 1]
                    && (!value[j - 1].starts_with('.') || segment.pattern.starts_with('.'))
                {
                    let runes: Vec<char> = value[j - 1].chars().collect();
                    next[j] = ends(&segment.atoms, &runes, 0)[runes.len()];
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

fn atoi(s: &str) -> Option<i64> {
    // Go's strconv.Atoi: optional sign, then decimal digits only.
    let digits = s.strip_prefix(['+', '-']).unwrap_or(s);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse().ok()
}

/// Brace expansion runs before segmentation; the bound avoids combinatorial allocation.
pub fn expand_braces(pattern: &str) -> Option<Vec<String>> {
    let b = pattern.as_bytes();
    let mut open = None;
    let (mut escaped, mut bracket) = (false, false);
    for (i, &ch) in b.iter().enumerate() {
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
        return Some(vec![pattern.to_string()]);
    };
    let mut depth = 1;
    let mut end = open + 1;
    while end < b.len() && depth > 0 {
        if b[end] == b'{' {
            depth += 1;
        }
        if b[end] == b'}' {
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
    for (i, &c) in inside.as_bytes().iter().enumerate() {
        match c {
            b'{' => nested += 1,
            b'}' => nested -= 1,
            b',' if nested == 0 => {
                parts.push(inside[at..i].to_string());
                at = i + 1;
            }
            _ => {}
        }
    }
    parts.push(inside[at..].to_string());
    if parts.len() == 1 {
        let fields: Vec<&str> = inside.split("..").collect();
        if fields.len() == 1 {
            let mut tails = expand_braces(&pattern[end + 1..])?;
            for t in &mut tails {
                *t = alloc::format!("{}{}", &pattern[..=end], t);
            }
            return Some(tails);
        }
        if fields.len() > 3 {
            return None;
        }
        let mut step: i64 = 1;
        if fields.len() == 3 {
            let n = atoi(fields[2])?;
            if n == 0 {
                return None;
            }
            step = n.abs();
        }
        let (mut lo, mut hi, mut alpha) = (atoi(fields[0]), atoi(fields[1]), false);
        if lo.is_none() || hi.is_none() {
            let (f0, f1) = (fields[0].as_bytes(), fields[1].as_bytes());
            if f0.len() != 1 || f1.len() != 1 || !brace_letter(f0[0]) || !brace_letter(f1[0]) {
                return None;
            }
            lo = Some(i64::from(f0[0]));
            hi = Some(i64::from(f1[0]));
            alpha = true;
        }
        let (lo, hi) = (lo?, hi?);
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
            parts.push(if alpha {
                char::from_u32(n as u32)
                    .map(String::from)
                    .unwrap_or_default()
            } else if width > 0 {
                let unsigned = alloc::format!("{}", n.abs());
                let padded = alloc::format!(
                    "{}{}",
                    "0".repeat(width.saturating_sub(unsigned.len())),
                    unsigned
                );
                if n < 0 {
                    alloc::format!("-{padded}")
                } else {
                    padded
                }
            } else {
                alloc::format!("{n}")
            });
            n += step;
        }
    }
    let mut result = Vec::new();
    for part in parts {
        let expanded = expand_braces(&alloc::format!(
            "{}{}{}",
            &pattern[..open],
            part,
            &pattern[end + 1..]
        ))?;
        if result.len() + expanded.len() > 1025 {
            return None;
        }
        result.extend(expanded);
    }
    Some(result)
}

#[cfg(test)]
mod tests {
    extern crate std;
    use super::*;

    fn m(pattern: &str, value: &str) -> bool {
        Glob::new(pattern).unwrap().matches(value)
    }

    #[test]
    fn basics() {
        assert!(m("*.ms", "a.ms"));
        assert!(!m("*.ms", ".a.ms"));
        assert!(m("src/**/*.ms", "src/a/b/c.ms"));
        assert!(m("src/**/*.ms", "src/c.ms"));
        assert!(!m("src/**", "src/.hidden/x"));
        assert!(m("a?c", "abc"));
        assert!(m("[a-c]x", "bx"));
        assert!(m("[!a-c]x", "dx"));
        assert!(!m("[!a-c]x", "bx"));
        assert!(m("{a,b}/c", "b/c"));
        assert!(m("f{1..3}", "f2"));
        assert!(m("f{01..03}", "f02"));
        assert!(m("+(ab)c", "ababc"));
        assert!(m("!(a)b", "xb"));
        assert!(m("@(a|b)", "b"));
        assert!(m("?(a)b", "b"));
        assert!(m("\\*", "*"));
    }

    #[test]
    fn invalid() {
        for p in [
            "[",
            "[]",
            "[a",
            "{a",
            "\\",
            "@(a",
            "{a..}",
            "{1..2..0}",
            "[a-]",
        ] {
            assert!(Glob::new(p).is_none(), "{p}");
        }
        assert!(Glob::new(&"a".repeat(4097)).is_none());
    }
}
