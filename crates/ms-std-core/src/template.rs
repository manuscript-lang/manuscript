//! Runtime-loaded plain-text templates. Leon owns the substitution grammar; the source
//! module owns lookup, output budgets and the public opaque compiled value.

use miette::Diagnostic;
use ms_rt::ffi::{RecList, Str, abi_record, native};

abi_record! {
    /// Internal source record, in declaration order.
    pub struct Part {
        pub variable: i64,
        pub text: Str,
        pub offset: i64,
    }
}

abi_record! {
    /// A parse result; an empty diagnostic means success, including an empty template.
    pub struct Compilation {
        pub parts: RecList<Part>,
        pub diagnostic: Str,
    }
}

fn compile(source: &str) -> Compilation {
    let parsed = match leon::Template::parse(source) {
        Ok(parsed) => parsed,
        Err(error) => {
            return Compilation {
                parts: RecList::new([]),
                diagnostic: Str::new(&diagnostic(source, &error)),
            };
        }
    };
    // Leon permits an opening brace inside a key. Our delimiters must be escaped
    // everywhere outside a placeholder's opening/closing pair.
    if let Some(key) = parsed.keys().find(|key| key.contains('{')) {
        let offset = key.as_ptr() as usize - source.as_ptr() as usize + key.find('{').unwrap_or(0);
        return Compilation {
            parts: RecList::new([]),
            diagnostic: Str::new(&at(source, offset, "unescaped opening brace in key")),
        };
    }
    Compilation {
        parts: RecList::new(parsed.items.iter().map(|item| {
            let (variable, text) = match item {
                leon::Item::Text(text) => (false, *text),
                leon::Item::Key(key) => (true, *key),
            };
            Part {
                variable: i64::from(variable),
                text: Str::new(text),
                // Leon's items are slices of source, including the escaped literal characters.
                offset: (text.as_ptr() as usize - source.as_ptr() as usize) as i64,
            }
        })),
        diagnostic: Str::new(""),
    }
}

fn diagnostic(source: &str, error: &leon::ParseError) -> String {
    let label = error.labels().and_then(|mut labels| labels.next());
    let offset = label.as_ref().map_or(0, |label| label.offset());
    let cause = label
        .as_ref()
        .and_then(|label| label.label())
        .unwrap_or("invalid template syntax");
    at(source, offset, cause)
}

fn at(source: &str, offset: usize, cause: &str) -> String {
    // Upstream inclusive-end spans can extend past EOF or split a scalar. Expose
    // only a valid starting position, rather than treating their length as a range.
    let mut offset = offset.min(source.len());
    while !source.is_char_boundary(offset) {
        offset -= 1;
    }
    let prefix = &source[..offset];
    let line = prefix.bytes().filter(|byte| *byte == b'\n').count() + 1;
    let column = prefix.rsplit('\n').next().unwrap_or("").chars().count() + 1;
    format!("{cause} at byte {offset}, line {line}, column {column}: {source}")
}

native! {
    fn msstd_template_compile(source: &str) -> out Compilation {
        compile(source)
    }
}

#[cfg(test)]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use ms_rt::ffi::AbiSlot;

    struct Owned(Compilation);

    impl core::ops::Deref for Owned {
        type Target = Compilation;
        fn deref(&self) -> &Compilation {
            &self.0
        }
    }

    impl Drop for Owned {
        fn drop(&mut self) {
            // SAFETY: this test wrapper owns the compilation and releases its fields once.
            unsafe {
                self.0.release();
            }
        }
    }

    #[test]
    fn parses_named_unicode_repeated_and_escaped_parts() {
        let parsed = Owned(compile("é { name }/{name} \\{literal\\} \\\\ {名}"));
        assert!(parsed.diagnostic.as_str().is_empty());
        let variables: Vec<_> = parsed
            .parts
            .as_slice()
            .iter()
            .filter(|part| part.variable != 0)
            .map(|part| (part.text.as_str(), part.offset))
            .collect();
        assert_eq!(variables, [("name", 5), ("name", 13), ("名", 35)]);
    }

    #[test]
    fn malformed_source_reports_original_span_and_cause() {
        for source in [
            "{}", "{  }", "left }", "{open", "bad\\x", "{a\\b}", "{{name}",
        ] {
            let parsed = Owned(compile(source));
            assert!(parsed.parts.as_slice().is_empty());
            let diagnostic = parsed.diagnostic.as_str();
            assert!(diagnostic.contains("at byte "), "{diagnostic}");
            assert!(diagnostic.contains(source), "{diagnostic}");
        }
        assert!(Owned(compile("")).diagnostic.as_str().is_empty());
    }

    #[test]
    fn diagnostics_at_eof_and_unicode_escapes_have_valid_locations() {
        for (source, location) in [
            ("{open", "at byte 0, line 1, column 1:"),
            ("x\\", "at byte 1, line 1, column 2:"),
            ("é\\🙂", "at byte 2, line 1, column 2:"),
            ("é\n\\🙂", "at byte 3, line 2, column 1:"),
            ("ok {a{b}", "at byte 5, line 1, column 6:"),
        ] {
            let parsed = Owned(compile(source));
            assert!(
                parsed.diagnostic.as_str().contains(location),
                "{}",
                parsed.diagnostic.as_str()
            );
        }
    }
}
