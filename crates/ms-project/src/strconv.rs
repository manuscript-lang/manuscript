//! Go `strconv.Unquote` for double-quoted strings and `strconv.Quote` for `%q`.

/// `strconv.Unquote` restricted to double-quoted strings (the manifest form).
/// Returns `None` where Go returns `ErrSyntax`. `\xNN` and octal escapes may
/// produce bytes that are not UTF-8; those become U+FFFD.
pub fn unquote(input: &str) -> Option<String> {
    let bytes = input.as_bytes();
    if bytes.len() < 2 || bytes[0] != b'"' {
        return None;
    }
    let mut out: Vec<u8> = Vec::new();
    let mut i = 1;
    loop {
        let c = *bytes.get(i)?;
        match c {
            b'"' => {
                i += 1;
                break;
            }
            b'\n' => return None,
            b'\\' => i = unescape(bytes, i + 1, &mut out)?,
            _ => {
                out.push(c);
                i += 1;
            }
        }
    }
    if i != bytes.len() {
        return None;
    }
    Some(String::from_utf8_lossy(&out).into_owned())
}

fn hex(bytes: &[u8], at: usize, count: usize) -> Option<u32> {
    let digits = bytes.get(at..at + count)?;
    let mut value = 0u32;
    for &d in digits {
        value = value * 16 + (d as char).to_digit(16)?;
    }
    Some(value)
}

/// Decode one escape whose backslash precedes `at`; returns the next index.
fn unescape(bytes: &[u8], at: usize, out: &mut Vec<u8>) -> Option<usize> {
    let c = *bytes.get(at)?;
    let simple = |byte: u8, out: &mut Vec<u8>| {
        out.push(byte);
        Some(at + 1)
    };
    match c {
        b'a' => simple(7, out),
        b'b' => simple(8, out),
        b'f' => simple(12, out),
        b'n' => simple(b'\n', out),
        b'r' => simple(b'\r', out),
        b't' => simple(b'\t', out),
        b'v' => simple(11, out),
        b'\\' => simple(b'\\', out),
        b'"' => simple(b'"', out),
        b'x' => {
            out.push(hex(bytes, at + 1, 2)? as u8);
            Some(at + 3)
        }
        b'u' | b'U' => {
            let count = if c == b'u' { 4 } else { 8 };
            let ch = char::from_u32(hex(bytes, at + 1, count)?)?;
            let mut buf = [0u8; 4];
            out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
            Some(at + 1 + count)
        }
        b'0'..=b'7' => {
            let digits = bytes.get(at..at + 3)?;
            let mut value = 0u32;
            for &d in digits {
                if !(b'0'..=b'7').contains(&d) {
                    return None;
                }
                value = value * 8 + (d - b'0') as u32;
            }
            if value > 255 {
                return None;
            }
            out.push(value as u8);
            Some(at + 3)
        }
        _ => None,
    }
}

/// `strconv.Quote` (the `%q` verb).
pub fn quote(text: &str) -> String {
    let mut out = String::from("\"");
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{7}' => out.push_str("\\a"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{b}' => out.push_str("\\v"),
            '\u{fffd}' => out.push_str("\\ufffd"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\x{:02x}", c as u32))
            }
            c if c.is_control() => {
                if (c as u32) < 0x10000 {
                    out.push_str(&format!("\\u{:04x}", c as u32));
                } else {
                    out.push_str(&format!("\\U{:08x}", c as u32));
                }
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unquote_cases() {
        assert_eq!(unquote("\"abc\"").as_deref(), Some("abc"));
        assert_eq!(unquote("\"a\\\"b\"").as_deref(), Some("a\"b"));
        assert_eq!(
            unquote("\"\\u00e9\\x41\\101\"").as_deref(),
            Some("\u{e9}AA")
        );
        assert_eq!(unquote("\"\\q\""), None);
        assert_eq!(unquote("\"a\" \"b\""), None);
        assert_eq!(unquote("\"abc"), None);
        assert_eq!(unquote("\"a\\\""), None);
        assert_eq!(unquote("\"\\'\""), None);
        assert_eq!(unquote("\"\\ud800\""), None);
        assert_eq!(unquote("\"\\400\""), None);
    }

    #[test]
    fn quote_cases() {
        assert_eq!(quote("a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"");
        assert_eq!(quote("/tmp/x y"), "\"/tmp/x y\"");
    }
}
