import Regex from "@std/regex.ms"

export extern fn msrt_string_from_scalars(values List[Int]) String!

export extern fn msrt_string_fields(hold text String) List[&String]

// Byte offset of the first scalar of `text` that occurs in `set`, or null.
export extern fn msrt_string_index_any(text, set String) Int?

// Text without the scalars of `set` at the start and, as selected, the end.
export extern fn msrt_string_trim_chars(
	text,
	set String,
	from_start,
	from_end Bool,
) String

export extern fn msstd_unicode_in_category(value Int, category String) Bool

export extern fn msstd_regex_compile(pattern String) Regex!

export extern fn msstd_regex_find_span(re Regex, text String) List[Int]?

export extern fn msstd_regex_captures(re Regex, text String) List[String]

export extern fn msstd_regex_captures_all(
	re Regex,
	text String,
	max_matches Int?,
) List[List[String]]!

// The first match's named groups that took part: name, text, name, text, ... in group
// order.
export extern fn msstd_regex_named_capture_pairs(re Regex, text String) List[String]

// Flat byte-offset pairs; captures start with the number of slots per match and use -1
// for absent groups.
export extern fn msstd_regex_find_all_spans(
	re Regex,
	text String,
	max_matches Int?,
) List[Int]!

export extern fn msstd_regex_capture_spans(
	re Regex,
	text String,
	max_captures Int?,
) List[Int]!

export extern fn msstd_regex_capture_all_spans(
	re Regex,
	text String,
	max_matches,
	max_captures Int?,
) List[Int]!
