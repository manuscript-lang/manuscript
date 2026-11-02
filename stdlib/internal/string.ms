import Regex from "@std/string.ms"

export extern fn msrt_string_from_scalars(values: List[Int]) String!

export extern fn msstd_regex_compile(pattern: String) Regex!

# Flat byte-offset pairs; captures start with the number of slots per match and use -1 for absent groups.
export extern fn msstd_regex_find_all_spans(
    re: Regex,
    text: String,
    max_matches: Int?
) List[Int]!

export extern fn msstd_regex_capture_spans(
    re: Regex,
    text: String,
    max_captures: Int?
) List[Int]!

export extern fn msstd_regex_capture_all_spans(
    re: Regex,
    text: String,
    max_matches: Int?,
    max_captures: Int?
) List[Int]!
