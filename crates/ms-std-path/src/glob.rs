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

/// Byte index of the `]` closing the class that opens `pattern`, skipping escaped characters.
fn class_end(pattern: &str) -> Option<usize> {
    let mut escaped = false;
    for (i, c) in pattern.char_indices().skip(1) {
        if escaped {
            escaped = false;
        } else if c == '\\' {
            escaped = true;
        } else if c == ']' {
            return Some(i);
        }
    }
    None
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
                let end = class_end(pattern)?;
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

/// A set of positions `0..=n`. Matching builds one per atom, so the usual case (a name of
/// up to 127 characters, a path of up to 63 parts) lives in a fixed array on the stack and
/// only longer input pays for a heap vector.
trait Positions: Sized {
    fn empty(n: usize) -> Self;
    fn insert(&mut self, i: usize);
    fn has(&self, i: usize) -> bool;
    fn first(&self) -> Option<usize>;
    fn is_empty(&self) -> bool;
    fn merge(&mut self, other: &Self);
}

struct Fixed<const W: usize>([u64; W]);

impl<const W: usize> Positions for Fixed<W> {
    fn empty(_n: usize) -> Self {
        Fixed([0; W])
    }
    fn insert(&mut self, i: usize) {
        self.0[i / 64] |= 1 << (i % 64);
    }
    fn has(&self, i: usize) -> bool {
        self.0[i / 64] >> (i % 64) & 1 == 1
    }
    fn first(&self) -> Option<usize> {
        self.0
            .iter()
            .position(|&w| w != 0)
            .map(|k| k * 64 + self.0[k].trailing_zeros() as usize)
    }
    fn is_empty(&self) -> bool {
        self.0.iter().all(|&w| w == 0)
    }
    fn merge(&mut self, other: &Self) {
        for (w, o) in self.0.iter_mut().zip(&other.0) {
            *w |= o;
        }
    }
}

struct Heap(Vec<u64>);

impl Positions for Heap {
    fn empty(n: usize) -> Self {
        Heap(vec![0; n / 64 + 1])
    }
    fn insert(&mut self, i: usize) {
        self.0[i / 64] |= 1 << (i % 64);
    }
    fn has(&self, i: usize) -> bool {
        self.0[i / 64] >> (i % 64) & 1 == 1
    }
    fn first(&self) -> Option<usize> {
        self.0
            .iter()
            .position(|&w| w != 0)
            .map(|k| k * 64 + self.0[k].trailing_zeros() as usize)
    }
    fn is_empty(&self) -> bool {
        self.0.iter().all(|&w| w == 0)
    }
    fn merge(&mut self, other: &Self) {
        for (w, o) in self.0.iter_mut().zip(&other.0) {
            *w |= o;
        }
    }
}

/// Positions reachable after matching `atoms` from `start`.
fn ends<S: Positions>(atoms: &[Atom], value: &[char], start: usize) -> S {
    let n = value.len();
    let mut positions = S::empty(n);
    positions.insert(start);
    for atom in atoms {
        let mut next = S::empty(n);
        match atom {
            Atom::Star => {
                if let Some(earliest) = positions.first() {
                    for at in earliest..=n {
                        next.insert(at);
                    }
                }
            }
            Atom::Literal(c) => {
                for (at, &ch) in value.iter().enumerate() {
                    if positions.has(at) && ch == *c {
                        next.insert(at + 1);
                    }
                }
            }
            Atom::Any => {
                for at in 0..n {
                    if positions.has(at) {
                        next.insert(at + 1);
                    }
                }
            }
            Atom::Class(class) => {
                for (at, &ch) in value.iter().enumerate() {
                    if positions.has(at) && class.matches(ch) {
                        next.insert(at + 1);
                    }
                }
            }
            Atom::Group(kind, alternatives) => {
                for at in (0..=n).filter(|&at| positions.has(at)) {
                    let mut accepted = S::empty(n);
                    for alt in alternatives {
                        accepted.merge(&ends::<S>(alt, value, at));
                    }
                    if *kind == '!' {
                        for e in at..=n {
                            if !accepted.has(e) {
                                next.insert(e);
                            }
                        }
                        continue;
                    }
                    next.merge(&accepted);
                    if *kind == '?' || *kind == '*' {
                        next.insert(at);
                    }
                    if *kind == '+' || *kind == '*' {
                        let mut seen = S::empty(n);
                        seen.insert(at);
                        let mut queue = alloc::collections::VecDeque::new();
                        for e in 0..=n {
                            if accepted.has(e) && !seen.has(e) {
                                seen.insert(e);
                                queue.push_back(e);
                            }
                        }
                        while let Some(position) = queue.pop_front() {
                            for alt in alternatives {
                                let reached = ends::<S>(alt, value, position);
                                for e in (0..=n).filter(|&e| reached.has(e)) {
                                    next.insert(e);
                                    if !seen.has(e) {
                                        seen.insert(e);
                                        queue.push_back(e);
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

/// Whether `atoms` match all of `value`.
fn matches_whole(atoms: &[Atom], value: &[char]) -> bool {
    let n = value.len();
    if n < 128 {
        ends::<Fixed<2>>(atoms, value, 0).has(n)
    } else {
        ends::<Heap>(atoms, value, 0).has(n)
    }
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
        // The characters of every part in one buffer, the parts as ranges into it.
        let mut chars: Vec<char> = Vec::with_capacity(value.len());
        let mut parts: Vec<(usize, usize)> = Vec::new();
        for part in value.split('/') {
            let start = chars.len();
            chars.extend(part.chars());
            parts.push((start, chars.len()));
        }
        self.0.iter().any(|alt| {
            if parts.len() < 64 {
                match_segments::<Fixed<1>>(&chars, &parts, alt)
            } else {
                match_segments::<Heap>(&chars, &parts, alt)
            }
        })
    }
}

fn match_segments<S: Positions>(
    chars: &[char],
    parts: &[(usize, usize)],
    pattern: &[Segment],
) -> bool {
    let n = parts.len();
    let dotted = |j: usize| {
        chars.get(parts[j - 1].0).is_some_and(|&c| c == '.') && parts[j - 1].0 < parts[j - 1].1
    };
    let mut previous = S::empty(n);
    previous.insert(0);
    for segment in pattern {
        let mut next = S::empty(n);
        if segment.pattern == "**" {
            if previous.has(0) {
                next.insert(0);
            }
            for j in 1..=n {
                if previous.has(j) || next.has(j - 1) && !dotted(j) {
                    next.insert(j);
                }
            }
        } else {
            for j in 1..=n {
                if previous.has(j - 1) && (!dotted(j) || segment.pattern.starts_with('.')) {
                    let (from, to) = parts[j - 1];
                    if matches_whole(&segment.atoms, &chars[from..to]) {
                        next.insert(j);
                    }
                }
            }
        }
        previous = next;
    }
    previous.has(n)
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
        let mut step: i128 = 1;
        if fields.len() == 3 {
            let n = atoi(fields[2])?;
            if n == 0 {
                return None;
            }
            step = i128::from(n).abs();
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
            || i128::from(lo - hi).abs() / step > 1024
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
        let mut n = i128::from(lo);
        let hi = i128::from(hi);
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
    fn brace_range_extreme_steps() {
        let one = |p: &str| expand_braces(p).unwrap();
        assert_eq!(one("{1..2..9223372036854775807}"), ["1"]);
        assert_eq!(one("{1..2..-9223372036854775808}"), ["1"]);
        assert_eq!(one("{2..1..9223372036854775807}"), ["2"]);
        assert_eq!(one("{2..1..-9223372036854775808}"), ["2"]);
        assert_eq!(one("{1..5..2}"), ["1", "3", "5"]);
        assert_eq!(one("{5..1..-2}"), ["5", "3", "1"]);
        assert_eq!(one("{01..03}"), ["01", "02", "03"]);
        assert_eq!(one("{a..c..2}"), ["a", "c"]);
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
    fn escaped_bracket_stays_in_class() {
        assert!(m("[\\]]", "]"));
        assert!(m("[a\\]]", "]"));
        assert!(m("[a\\]]x", "ax"));
        assert!(!m("[\\]]", "a"));
        assert!(Glob::new("[a").is_none());
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
