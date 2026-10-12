import {from_scalars, StringError, StringBuilder} from "@std/string.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "Unicode scalar indexing differs from byte length":
    let text = "aé🙂"
    if text.byte_length() != 7 or text.scalar_length() != 3: return panic("Unicode lengths")
    if text.scalar_values() != [97, 233, 128578]: return panic("scalar values")
    if text.at(-1) != some(value: "🙂") or text.scalar_at(1) != some(value: 233): return panic("scalar indexing")
    if not text.at(3).is_none(): return panic("out of bounds optional")
    if value(from_scalars(text.scalar_values())) != text: return panic("scalar roundtrip")
    if value(text.slice_scalars(start: 1, end: 3)) != "é🙂": return panic("scalar slice")
    if value("é".normalize(form: "NFC")) != "é": return panic("normalization")

test "strings honor omitted none zero and explicit output limits":
    if value("ab".repeat(count: 2)) != "abab": return panic("omitted repeat budget")
    if value("ab".repeat(count: 2, max_bytes: none)) != "abab": return panic("none repeat budget")
    if value("ab".repeat(count: 0, max_bytes: some(value: 0))) != "": return panic("zero repeat")
    let limited: Result[String, StringError] = error(cause: StringError.LimitExceeded)
    if "é".repeat(count: 2, max_bytes: some(value: 3)) != limited: return panic("byte budget")
    if value("x".pad_start(target_length: 3, padding: "ab")) != "abx": return panic("pad start")
    if value("x".pad_end(target_length: 3, padding: "ab")) != "xab": return panic("pad end")
    if value("aa".replace_all(old: "a", new: "xy")) != "xyxy": return panic("replace all")
    if "a,,b".split(separator: ",", max_parts: some(value: 2)) != ["a", ""]: return panic("split truncation")
    if " \té \n".trim() != "é": return panic("trim")
    let invalid: Result[String, StringError] = error(cause: StringError.InvalidInput)
    if "a".normalize(form: "invalid") != invalid: return panic("normalization form")
    let scalar_error: Result[String, StringError] = error(cause: StringError.InvalidInput)
    if from_scalars([55296]) != scalar_error: return panic("surrogate scalar")

test "bytes copy slice search and UTF8 validation":
    let data = Bytes(values: [0, 1, 255, 1])
    if data.at(-1) != some(value: 1): return panic("negative byte index")
    if not data.at(4).is_none(): return panic("missing byte")
    if data.index_of(Bytes(values: [1])) != some(value: 1): return panic("byte search")
    if data.last_index_of(Bytes(values: [1])) != some(value: 3): return panic("last byte search")
    if data.slice(start: 1, end: 3) != Bytes(values: [1, 255]): return panic("byte slice")
    if data.reverse() != Bytes(values: [1, 255, 1, 0]): return panic("byte reverse")
    let copied = data.clone().with_value(index: 0, value: 42)
    if copied.at(0) != some(value: 42) or data.at(0) != some(value: 0): return panic("clone storage")
    if not Bytes(values: [255]).to_text().is_none(): return panic("invalid UTF8 accepted")
    if "é".to_bytes().to_text() != some(value: "é"): return panic("UTF8 roundtrip")

test "string and bytes builders freeze idempotently":
    let text = StringBuilder()
    text.append("é")
    text.append("🙂")
    if text.freeze() != "é🙂" or text.freeze() != "é🙂": return panic("string freeze")
    let bytes = BytesBuilder()
    bytes.append(0)
    bytes.concat(Bytes(values: [255, 1]))
    if bytes.freeze() != Bytes(values: [0, 255, 1]) or bytes.freeze() != Bytes(values: [0, 255, 1]): return panic("bytes freeze")
