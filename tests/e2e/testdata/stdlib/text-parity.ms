import {compile, RegexMatch, RegexError} from "@std/regex.ms"
import Bytes from "@std/bytes.ms"
import hex_decode from "@std/encoding.ms"
import panic from "@std/faults.ms"

test "byte offset search uses absolute indexes within immutable views":
    let original = Bytes([255, 0, 1, 0, 2, 255])
    let view = original.slice(1, 5).unwrap()
    let zero = Bytes([0])
    if view.index_of_from(zero, 1) != some(2): return panic("absolute offset")
    if not view.index_of_from(zero, 3).is_none(): return panic(
        "search past final match"
    )
    if view.index_of_from(
        Bytes([]),
        4
    ) != some(4): return panic("empty end match")

    let stored: fn(value: Bytes, start: Int) -> Optional[Int] = view.index_of_from
    if stored(zero, 0) != some(0): return panic("stored byte search")

    let old: fn(value: Bytes) -> Optional[Int] = view.index_of
    if old(zero) != some(0): return panic("existing search signature")
    if view.to_hex() != "00010002": return panic("lowercase hex")
    if hex_decode(view.to_hex()).unwrap() != view: return panic("hex round trip")
    if Bytes([]).to_hex() != "": return panic("empty hex")
    if original.to_hex() != "ff00010002ff": return panic("changed original bytes")

test "regex first match carries scalar positions and optional captures":
    let regex = compile("(é)(x)?()").unwrap()
    let found: RegexMatch = regex.find("🙂é!").unwrap()
    if (
        found.text != "é"
        or found.start != 1
        or found.end != 2
    ): return panic("scalar position")
    if found.groups != [some("é"), none, some("")]: return panic("capture presence")

    let stored: fn(text: String) -> Optional[RegexMatch] = regex.find
    if not stored("no match").is_none(): return panic("missing first match")

    let empty = compile("$").unwrap().find("é🙂").unwrap()
    if (
        empty.start != 2
        or empty.end != 2
        or empty.text != ""
        or not empty.groups.is_empty()
    ): return panic("empty terminal match")

    found.groups.set(0, none)
    if regex.find("🙂é!").unwrap().groups.first().unwrap() != some("é"): return panic(
        "shared groups"
    )

test "regex split excludes captures and truncates optional caps":
    let regex = compile("(,)").unwrap()
    if regex.split(",a,,b,").unwrap() != ["", "a", "", "b", ""]: return panic(
        "retained empty parts"
    )
    if regex.split(",a,,b,", 2).unwrap() != ["", "a"]: return panic("truncating cap")
    if regex.split("abc", none).unwrap() != ["abc"]: return panic("none cap")
    if not regex.split("abc", 0).unwrap().is_empty(): return panic("zero cap")
    if regex.split("").unwrap() != [""]: return panic("empty input")

    let scalar = compile("").unwrap()
    if scalar.split("é🙂").unwrap() != ["é", "🙂"]: return panic("zero width Unicode")
    if scalar.split("é🙂", 1).unwrap() != ["é"]: return panic("zero width cap")
    if not scalar.split("").unwrap().is_empty(): return panic("empty regex and input")

    let stored: fn(text: String, max_parts: Optional[Int]) -> Result[
        List[String],
        RegexError
    ] = regex.split
    if stored("a,b", none).unwrap() != ["a", "b"]: return panic("stored split")

    match regex.split("abc", -1):
        ok(_): return panic("negative cap accepted")
        error(cause):
            if cause != RegexError.InvalidInput: return panic("negative cap identity")
