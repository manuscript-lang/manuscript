import StringError, Regex, RegexError from "@std/string.ms"

export extern fn msrt_string_from_scalars(values: List[Int]) String!StringError

export extern fn msrt_regex_compile(pattern: String) Regex!RegexError
