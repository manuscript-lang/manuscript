export extern fn msstd_unicode_is_alphabetic(value: Int) Bool

export extern fn msstd_unicode_is_alphanumeric(value: Int) Bool

export extern fn msstd_unicode_is_numeric(value: Int) Bool

export extern fn msstd_unicode_is_lowercase(value: Int) Bool

export extern fn msstd_unicode_is_uppercase(value: Int) Bool

export extern fn msstd_unicode_is_whitespace(value: Int) Bool

export extern fn msstd_unicode_is_control(value: Int) Bool

export extern fn msstd_unicode_is_ascii(value: Int) Bool

export extern fn msstd_unicode_fields(text: String) List[String]

// Text without the scalars of `set` at the start and, as selected, the end.
export extern fn msstd_string_trim_chars(text: String, set: String, from_start: Bool, from_end: Bool) String

// Display width of text (ambiguous characters narrow); controls, U+2028 and U+2029 are
// EBADMSG.
export extern fn msstd_unicode_display_width(text: String) Int!
