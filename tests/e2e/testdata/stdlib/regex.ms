import {compile, RegexError} from "@std/regex.ms"
import panic from "@std/faults.ms"

test "regex receivers execute matching replacement and empty results":
    let regex = try compile("[0-9]+")
    if not regex.matches("a12b"): return panic("match")
    if regex.matches("abc"): return panic("false match")
    if (try regex.find_all("a12b3")) != ["12", "3"]: return panic("find all")
    if not (try regex.find_all("abc", 0)).is_empty(): return panic("empty match budget")
    if (try regex.replace_all("a12b3", "#")) != "a#b#": return panic("replace")

test "regex rejects invalid expressions and exhausted budgets":
    let invalid = compile("[")
    if not invalid.is_error(): return panic("invalid pattern accepted")
    if invalid.err() != RegexError.InvalidData: return panic("pattern error identity")

    let regex = try compile("[0-9]+")
    let limited: Result[List[String], RegexError] = error(RegexError.LimitExceeded)
    if regex.find_all("1 2", 1) != limited: return panic("match budget")

    let output_limit: Result[String, RegexError] = error(RegexError.LimitExceeded)
    if (regex.replace_all("1", "long", 3) != output_limit): return panic(
        "output budget"
    )
