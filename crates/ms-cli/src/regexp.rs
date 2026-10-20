//! Validation of `--match` / `--exclude` patterns. Patterns use RE2 syntax, as in the
//! `regex` crate. Error text follows the
//! `error parsing regexp: <reason>: `<fragment>`` form for the common mistakes.

pub fn validate(pattern: &str) -> Result<(), String> {
    match regex::Regex::new(pattern) {
        Ok(_) => Ok(()),
        Err(error) => Err(go_error(pattern, &error)),
    }
}

fn go_error(pattern: &str, error: &regex::Error) -> String {
    let text = error.to_string();
    let detail = text.lines().last().unwrap_or("").trim();
    let reason = if detail.contains("unclosed group") {
        Some(("missing closing )", pattern.to_string()))
    } else if detail.contains("unopened group") {
        Some(("unexpected )", pattern.to_string()))
    } else if detail.contains("unclosed character class") {
        Some((
            "missing closing ]",
            pattern[pattern.rfind('[').unwrap_or(0)..].to_string(),
        ))
    } else if detail.contains("repetition operator missing expression") {
        let at = pattern.find(['*', '+', '?']).unwrap_or(0);
        Some((
            "missing argument to repetition operator",
            pattern[at..=at].to_string(),
        ))
    } else if detail.contains("incomplete escape sequence") {
        Some(("trailing backslash at end of expression", String::new()))
    } else {
        None
    };
    match reason {
        Some((message, fragment)) => format!("error parsing regexp: {message}: `{fragment}`"),
        None => format!("error parsing regexp: {detail}: `{pattern}`"),
    }
}

#[cfg(test)]
mod tests {
    use super::validate;

    #[test]
    fn go_style_errors() {
        assert!(validate("a.*b|c").is_ok());
        assert_eq!(
            validate("(a").unwrap_err(),
            "error parsing regexp: missing closing ): `(a`"
        );
        assert_eq!(
            validate("a)").unwrap_err(),
            "error parsing regexp: unexpected ): `a)`"
        );
        assert_eq!(
            validate("*a").unwrap_err(),
            "error parsing regexp: missing argument to repetition operator: `*`"
        );
        assert_eq!(
            validate("[a").unwrap_err(),
            "error parsing regexp: missing closing ]: `[a`"
        );
    }
}
