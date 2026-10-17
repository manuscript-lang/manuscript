import {compile, Regex, RegexError} from "@std/regex.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "regex receivers execute matching replacement and empty results":
    let regex = compile("[0-9]+") | value
    if not regex.matches("a12b"): return panic("match")
    if regex.matches("abc"): return panic("false match")
    if value(regex.find_all(text: "a12b3")) != ["12", "3"]: return panic("find all")
    if not value(regex.find_all(text: "abc", max_matches: 0)).is_empty(): return panic(
        "empty match budget"
    )
    if value(regex.replace_all(text: "a12b3", replacement: "#")) != "a#b#": return panic(
        "replace"
    )

test "regex rejects invalid expressions and exhausted budgets":
    let invalid_pattern = compile("[")
    if invalid_pattern.is_ok(): return panic("invalid pattern accepted")
    if invalid_pattern.unwrap_error() != RegexError.InvalidData: return panic(
        "pattern error identity"
    )

    let regex = compile("[0-9]+") | value
    let limited: Result[List[String], RegexError] = error(RegexError.LimitExceeded)
    if regex.find_all(text: "1 2", max_matches: 1) != limited: return panic(
        "match budget"
    )

    let output_limit: Result[String, RegexError] = error(RegexError.LimitExceeded)
    if (regex.replace_all(text: "1", replacement: "long", max_bytes: 3) != output_limit): return panic(
        "output budget"
    )
