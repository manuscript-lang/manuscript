//! Character reference decoding and escaping, ported from `html/escape.go`.
use crate::entity::{DOUBLE, SINGLE};
use alloc::string::String;
use alloc::vec::Vec;

/// All entities that do not end with ';' are 6 or fewer bytes long.
const LONGEST_WITHOUT_SEMICOLON: usize = 6;

/// Windows-1252 replacements for numeric references 0x80..=0x9F.
const REPLACEMENT: [u32; 32] = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039,
    0x0152, 0x008D, 0x017D, 0x008F, 0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
];

fn push_rune(out: &mut Vec<u8>, r: u32) {
    let ch = char::from_u32(r).unwrap_or('\u{FFFD}');
    let mut buf = [0u8; 4];
    out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
}

/// The references escaping produces; they skip the table search.
static COMMON: [(&str, u32); 4] = [
    ("amp;", 0x26),
    ("lt;", 0x3C),
    ("gt;", 0x3E),
    ("quot;", 0x22),
];

fn lookup(name: &str) -> Option<&'static (&'static str, u32)> {
    if let Some(e) = COMMON.iter().find(|e| e.0 == name) {
        return Some(e);
    }
    SINGLE
        .binary_search_by(|e| e.0.as_bytes().cmp(name.as_bytes()))
        .ok()
        .map(|i| &SINGLE[i])
}

fn lookup2(name: &str) -> Option<[u32; 2]> {
    DOUBLE
        .binary_search_by(|e| e.0.as_bytes().cmp(name.as_bytes()))
        .ok()
        .map(|i| DOUBLE[i].1)
}

/// Reads a reference like `&lt;` at `s[0] == b'&'`, appending its replacement (or the consumed
/// bytes unchanged) to `out`, and returns the number of bytes consumed.
fn unescape_entity(s: &[u8], out: &mut Vec<u8>, attribute: bool) -> usize {
    let literal = |out: &mut Vec<u8>, n: usize| {
        out.extend_from_slice(&s[..n]);
        n
    };
    if s.len() <= 1 {
        return literal(out, 1);
    }
    let mut i = 1;
    if s[i] == b'#' {
        i += 1;
        let hex = matches!(s.get(i), Some(b'x' | b'X'));
        if hex {
            i += 1;
        }
        let radix = if hex { 16 } else { 10 };
        let digits_start = i;
        // Saturate above U+10FFFF so a long digit run maps to U+FFFD instead of wrapping into a scalar.
        let mut x: u32 = 0;
        while let Some(d) = s.get(i).and_then(|&c| char::from(c).to_digit(radix)) {
            x = (x * radix + d).min(0x11_0000);
            i += 1;
        }
        let terminated = s.get(i) == Some(&b';');
        // The tokenizer oracle (Go's x/net/html) decodes a digitless `&#x;` as U+FFFD; `unescape_string`
        // keeps that one spelling literal. Every other digitless reference stays literal.
        if i == digits_start && !(hex && terminated) {
            return literal(out, 1);
        }
        if terminated {
            i += 1;
        }
        let r = if (0x80..=0x9F).contains(&x) {
            REPLACEMENT[(x - 0x80) as usize]
        } else if x == 0 || (0xD800..=0xDFFF).contains(&x) || x > 0x10FFFF {
            0xFFFD
        } else {
            x
        };
        push_rune(out, r);
        return i;
    }

    while i < s.len() {
        let c = s[i];
        i += 1;
        if c.is_ascii_alphanumeric() {
            continue;
        }
        if c != b';' {
            i -= 1;
        }
        break;
    }
    // The name is ASCII alphanumerics plus an optional ';', so it is valid UTF-8.
    let Ok(name) = core::str::from_utf8(&s[1..i]) else {
        return literal(out, i);
    };
    if name.is_empty() || (attribute && !name.ends_with(';') && s.len() > i && s[i] == b'=') {
        // No-op: the text stays literal.
    } else if let Some(&(_, r)) = lookup(name) {
        push_rune(out, r);
        return i;
    } else if let Some(rs) = lookup2(name) {
        push_rune(out, rs[0]);
        push_rune(out, rs[1]);
        return i;
    } else if !attribute {
        let max_len = (name.len() - 1).min(LONGEST_WITHOUT_SEMICOLON);
        for j in (2..=max_len).rev() {
            if let Some(&(_, r)) = lookup(&name[..j]) {
                push_rune(out, r);
                return j + 1;
            }
        }
    }
    literal(out, i)
}

/// Unescapes the references in `b`, so that `a&lt;b` becomes `a<b`. `attribute` selects the
/// attribute-value rules.
pub fn unescape(b: &[u8], attribute: bool) -> Vec<u8> {
    if find_any(b, *b"&").is_none() {
        // No references: one copy.
        return b.to_vec();
    }
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        // Copy the run up to the next reference in one piece.
        let run = find_any(&b[i..], *b"&").unwrap_or(b.len() - i);
        out.extend_from_slice(&b[i..i + run]);
        i += run;
        if i < b.len() {
            i += unescape_entity(&b[i..], &mut out, attribute);
        }
    }
    out
}

/// `html.UnescapeString`, except that `&#x;` and `&#X;` (a hexadecimal reference without digits)
/// stay literal as HTML5 specifies.
pub fn unescape_string(s: &str) -> String {
    let b = s.as_bytes();
    if find_any(b, *b"&").is_none() {
        // No references: one copy.
        return String::from(s);
    }
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        let run = find_any(&b[i..], *b"&").unwrap_or(b.len() - i);
        out.extend_from_slice(&b[i..i + run]);
        i += run;
        if i == b.len() {
            break;
        }
        if b[i..].starts_with(b"&#x;") || b[i..].starts_with(b"&#X;") {
            out.extend_from_slice(&b[i..i + 4]);
            i += 4;
        } else {
            i += unescape_entity(&b[i..], &mut out, false);
        }
    }
    String::from_utf8(out).unwrap_or_default()
}

/// The offset of the first byte of `b` that is in `set`, eight bytes per step: a byte equal to
/// `c` makes `x ^ c * LO` have a zero byte, which the subtract-and-mask test flags; the lowest
/// flagged bit is always a true match.
#[inline]
fn find_any<const N: usize>(b: &[u8], set: [u8; N]) -> Option<usize> {
    const LO: u64 = 0x0101_0101_0101_0101;
    const HI: u64 = 0x8080_8080_8080_8080;
    let (chunks, rest) = b.as_chunks::<8>();
    let mut at = 0;
    for w in chunks {
        let x = u64::from_le_bytes(*w);
        let mut hit = 0;
        for c in set {
            let y = x ^ (LO * u64::from(c));
            hit |= y.wrapping_sub(LO) & !y & HI;
        }
        if hit != 0 {
            return Some(at + hit.trailing_zeros() as usize / 8);
        }
        at += 8;
    }
    rest.iter().position(|c| set.contains(c)).map(|p| at + p)
}

/// `html.EscapeString`: escapes `<`, `>`, `&`, `'` and `"`.
pub fn escape_string(s: &str) -> String {
    let mut rest = s;
    let Some(first) = find_any(rest.as_bytes(), *b"&'<>\"") else {
        // Nothing to escape: one copy.
        return String::from(s);
    };
    let mut out = String::with_capacity(s.len() + s.len() / 4 + 8);
    let mut at = first;
    loop {
        let replacement = match rest.as_bytes()[at] {
            b'&' => "&amp;",
            b'\'' => "&#39;",
            b'<' => "&lt;",
            b'>' => "&gt;",
            _ => "&#34;",
        };
        // The special bytes are ASCII, so `at` ends on a character boundary.
        out.push_str(&rest[..at]);
        out.push_str(replacement);
        rest = &rest[at + 1..];
        match find_any(rest.as_bytes(), *b"&'<>\"") {
            Some(next) => at = next,
            None => break,
        }
    }
    out.push_str(rest);
    out
}
