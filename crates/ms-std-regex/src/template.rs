//! Capped template expansion checks borrowed fragments before copying them. Keep the
//! regex crate's replacement syntax; uncapped calls use `Captures::expand` directly.
use alloc::string::String;
use ms_rt::ffi::Fail;

pub(super) fn expand(
    captures: &regex::Captures<'_>,
    mut template: &str,
    out: &mut String,
    max: usize,
) -> Result<(), Fail> {
    while let Some(at) = template.find('$') {
        append(out, &template[..at], max)?;
        template = &template[at + 1..];
        if let Some(rest) = template.strip_prefix('$') {
            append(out, "$", max)?;
            template = rest;
            continue;
        }
        let reference = if let Some(braced) = template.strip_prefix('{') {
            braced.find('}').map(|end| (&braced[..end], end + 2))
        } else {
            let end = template
                .bytes()
                .take_while(|b| b.is_ascii_alphanumeric() || *b == b'_')
                .count();
            (end > 0).then_some((&template[..end], end))
        };
        let Some((name, end)) = reference else {
            // An unfinished braced reference is literal, but later dollars may
            // still start valid references, just as in the upstream expander.
            append(out, "$", max)?;
            continue;
        };
        // Preserve upstream usize parsing, including braced +1 and leading zeroes.
        let capture = if let Ok(index) = name.parse::<usize>() {
            captures.get(index)
        } else {
            captures.name(name)
        };
        if let Some(capture) = capture {
            append(out, capture.as_str(), max)?;
        }
        template = &template[end..];
    }
    append(out, template, max)
}

fn append(out: &mut String, text: &str, max: usize) -> Result<(), Fail> {
    if text.len() > max - out.len() {
        return Err(Fail::LimitExceeded);
    }
    out.push_str(text);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn oversized_capture_and_literal_are_rejected_before_copying() {
        let re = regex::Regex::new("(?P<large>.+)").unwrap();
        let text = "x".repeat(1024 * 1024);
        let captures = re.captures(&text).unwrap();
        for template in ["$0", "$1$1", "${large}", "${+1}", &text] {
            let mut out = String::new();
            assert_eq!(
                expand(&captures, template, &mut out, 0),
                Err(Fail::LimitExceeded)
            );
            assert!(out.is_empty());
            assert_eq!(out.capacity(), 0);
        }
        let mut out = String::from("é");
        assert_eq!(
            expand(&captures, "$1", &mut out, 2),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(out, "é");
        let mut out = String::new();
        assert_eq!(
            expand(&captures, "ok$1", &mut out, 2),
            Err(Fail::LimitExceeded)
        );
        assert_eq!(out, "ok");
    }

    #[test]
    fn capped_expansion_matches_upstream_syntax_and_utf8_budgets() {
        let re = crate::compile("(?P<a>é)(?P<名字>🙂)(x)?()").unwrap();
        let captures = re.pattern.captures("é🙂").unwrap();
        for template in [
            "",
            "text",
            "é🙂",
            "$",
            "$$",
            "$$$",
            "$$$$",
            "$0",
            "$1",
            "$2",
            "$3",
            "$4",
            "$5",
            "$a",
            "${a}",
            "${名字}",
            "$名字",
            "${+1}",
            "${01}",
            "${0}",
            "$1x",
            "${1}x",
            "$1_",
            "${}",
            "${ }",
            "${1 2}",
            "$9999999999999999999999999999999999999999",
            "${missing}",
            "${a",
            "${a $1",
            "${a ${名字}",
            "${a}$$${2}:$3$4",
            "\0$1\n",
        ] {
            let mut expected = String::new();
            captures.expand(template, &mut expected);
            for prefix in ["", "é"] {
                let full = alloc::format!("{prefix}{expected}");
                for max in prefix.len()..=full.len() + 1 {
                    let mut out = String::from(prefix);
                    let result = expand(&captures, template, &mut out, max);
                    if full.len() <= max {
                        assert_eq!(result, Ok(()), "{template:?}, {max}");
                        assert_eq!(out, full, "{template:?}, {max}");
                    } else {
                        assert_eq!(result, Err(Fail::LimitExceeded), "{template:?}, {max}");
                        assert!(out.len() <= max, "{template:?}, {max}");
                    }
                }
            }
            let text = "é🙂 é🙂";
            let expected = re.replace_template(text, template, None).unwrap();
            assert_eq!(
                re.replace_template(text, template, Some(expected.len() as i64)),
                Ok(expected.clone())
            );
            if !expected.is_empty() {
                assert_eq!(
                    re.replace_template(text, template, Some(expected.len() as i64 - 1)),
                    Err(Fail::LimitExceeded)
                );
            }
        }
    }
}
