//! `.env` file parsing.
//!
//! The whole text is parsed before anything is applied. Quoted values may span lines; comments
//! outside quotes and an `export ` prefix are accepted.
use alloc::string::String;
use alloc::vec::Vec;

pub fn parse(text: &str) -> Option<Vec<(String, String)>> {
    let mut text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let mut entries = Vec::new();
    while !text.is_empty() {
        text = text.trim_start_matches([' ', '\t', '\r', '\n']);
        if text.is_empty() {
            break;
        }
        if text.starts_with('#') {
            text = text.split_once('\n').map_or("", |(_, rest)| rest);
            continue;
        }
        text = text.strip_prefix("export ").unwrap_or(text);
        let at = text.find('=').filter(|&at| at >= 1)?;
        let key = text[..at].trim();
        if key.contains([' ', '\t', '\r', '\n', '\0']) {
            return None;
        }
        for (i, c) in key.char_indices() {
            if !(c == '_' || c.is_ascii_alphabetic() || (i > 0 && c.is_ascii_digit())) {
                return None;
            }
        }
        text = text[at + 1..].trim_start_matches([' ', '\t']);
        let value: &str;
        if let Some(quote) = text
            .chars()
            .next()
            .filter(|c| matches!(c, '\'' | '"' | '`'))
        {
            let end = text[1..].find(quote)?;
            value = &text[1..end + 1];
            text = &text[end + 2..];
            let (line, rest) = text.split_once('\n').unwrap_or((text, ""));
            let line = line.trim();
            if !line.is_empty() && !line.starts_with('#') {
                return None;
            }
            text = rest;
        } else {
            let (line, rest) = text.split_once('\n').unwrap_or((text, ""));
            value = line.split_once('#').map_or(line, |(v, _)| v).trim();
            text = rest;
        }
        if value.contains('\0') {
            return None;
        }
        entries.push((String::from(key), String::from(value)));
    }
    Some(entries)
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    fn pairs(text: &str) -> Option<Vec<(&'static str, &'static str)>> {
        parse(text).map(|v| {
            v.into_iter()
                .map(|(k, v)| (&*String::leak(k), &*String::leak(v)))
                .collect()
        })
    }

    #[test]
    fn accepts_the_documented_forms() {
        let text =
            "# c\nA=1\nexport B = two # trailing\nC='x # y'\nD=\"multi\nline\" # after\n`E`\n";
        assert_eq!(pairs("\u{feff}A=1\n"), Some(vec![("A", "1")]));
        assert_eq!(
            pairs(
                "# c\nA=1\nexport B = two # trailing\nC='x # y'\nD=\"multi\nline\" # after\nF=\n"
            ),
            Some(vec![
                ("A", "1"),
                ("B", "two"),
                ("C", "x # y"),
                ("D", "multi\nline"),
                ("F", "")
            ])
        );
        assert_eq!(pairs(text), None);
    }

    #[test]
    fn rejects_malformed_input() {
        for bad in [
            "=x",
            "A B=1",
            "1A=2",
            "A='open",
            "A='x' junk",
            "A=x\n-B=1",
            "NOEQUALS",
        ] {
            assert_eq!(parse(bad), None, "{bad:?}");
        }
    }
}
