//! C ABI shims for `@std/data/html.ms` (`msstd_html_*`): HTML escaping and character-reference
//! decoding. Parsing lives in Manuscript.
//! ms: domain HTML

use alloc::string::String;
use ms_rt::ffi::native;

native! {
    // ms: leaf
    fn msstd_html_escape(text: &str) -> String {
        crate::escape(text)
    }

    // ms: leaf
    fn msstd_html_unescape(text: &str) -> String {
        crate::unescape(text)
    }

    /// Decodes references as the tokenizer does, in attribute-value mode when `attribute`.
    // ms: leaf
    fn msstd_html_decode(text: &str, attribute: bool) -> String {
        String::from_utf8_lossy(&crate::escape::unescape(text.as_bytes(), attribute)).into_owned()
    }
}
