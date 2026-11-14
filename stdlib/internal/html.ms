// Native character-reference primitives for `@std/data/html.ms`.
export extern fn msstd_html_escape(text: String) String

// Decodes character references the way the public `unescape` does.
export extern fn msstd_html_unescape(text: String) String

// Decodes character references as the tokenizer does: in an attribute value when
// `attribute` is set, where an unterminated reference followed by `=` or an
// alphanumeric stays literal.
export extern fn msstd_html_decode(text: String, attribute: Bool) String
