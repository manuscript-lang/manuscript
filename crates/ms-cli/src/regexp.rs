//! Validation of `--match` / `--exclude` patterns, using the `regex` crate's syntax and errors.

pub fn validate(pattern: &str) -> Result<(), String> {
    regex::Regex::new(pattern)
        .map(|_| ())
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::validate;

    #[test]
    fn reports_regex_crate_errors() {
        assert!(validate("a.*b|c").is_ok());
        for bad in ["(a", "a)", "*a", "[a"] {
            assert!(validate(bad).is_err(), "{bad}");
        }
    }
}
