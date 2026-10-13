import {from_scalars, StringError, StringBuilder} from "@std/string.ms"
import {Bytes, BytesBuilder, values} from "@std/bytes.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

test "Unicode scalar indexing differs from byte length":
    let text = "aé🙂"
    if text.byte_length() != 7 or text.scalar_length() != 3: return panic(
        "Unicode lengths"
    )
    if text.scalar_values() != [97, 233, 128578]: return panic("scalar values")
    if text.at(-1) != some("🙂") or text.scalar_at(1) != some(233): return panic(
        "scalar indexing"
    )
    if not text.at(3).is_none(): return panic("out of bounds optional")
    if value(
        from_scalars(text.scalar_values())
    ) != text: return panic("scalar roundtrip")
    if value(text.slice_scalars(start: 1, end: 3)) != "é🙂": return panic("scalar slice")
    if value("é".normalize(form: "NFC")) != "é": return panic("normalization")

test "strings honor omitted none zero and explicit output limits":
    if value("ab".repeat(count: 2)) != "abab": return panic("omitted repeat budget")
    if value("ab".repeat(count: 2)) != "abab": return panic(
        "none repeat budget"
    )
    if value(
        "ab".repeat(
            count: 0,
            max_bytes: 0
        )
    ) != "": return panic("zero repeat")

    let limited: Result[String, StringError] = error(StringError.LimitExceeded)
    if "é".repeat(
        count: 2,
        max_bytes: 3
    ) != limited: return panic("byte budget")
    if value("x".pad_start(target_length: 3, padding: "ab")) != "abx": return panic(
        "pad start"
    )
    if value("x".pad_end(target_length: 3, padding: "ab")) != "xab": return panic(
        "pad end"
    )
    if "ab".repeat(count: 4611686018427387904) != limited: return panic("repeat huge")
    if "ab".pad_start(
        target_length: 9223372036854775807,
        padding: "x"
    ) != limited: return panic("pad start huge")
    if (
        "ab".pad_end(
            target_length: 4611686018427387904,
            padding: "xyz",
            max_bytes: 9223372036854775807
        ) != limited
    ): return panic("pad end huge")
    if value("aa".replace_all(old: "a", new: "xy")) != "xyxy": return panic(
        "replace all"
    )
    if "a,,b".split(
        separator: ",",
        max_parts: 2
    ) != ["a", ""]: return panic("split truncation")
    if " \té \n".trim() != "é": return panic("trim")

    let invalid: Result[String, StringError] = error(StringError.InvalidInput)
    if "a".normalize(form: "invalid") != invalid: return panic("normalization form")

    let scalar_error: Result[String, StringError] = error(
        StringError.InvalidInput
    )
    if from_scalars([55296]) != scalar_error: return panic("surrogate scalar")

test "bytes copy slice search and UTF8 validation":
    let data = Bytes([0, 1, 255, 1])
    if data.at(-1) != some(1): return panic("negative byte index")
    if not data.at(4).is_none(): return panic("missing byte")
    if data.index_of(Bytes([1])) != some(1): return panic("byte search")
    if data.last_index_of(Bytes([1])) != some(3): return panic(
        "last byte search"
    )
    if data.slice(start: 1, end: 3) != Bytes([1, 255]): return panic(
        "byte slice"
    )
    if data.reverse() != Bytes([1, 255, 1, 0]): return panic("byte reverse")

    let copied = data.clone().with_value(index: 0, value: 42)
    if copied.at(0) != some(42) or data.at(0) != some(0): return panic(
        "clone storage"
    )
    if not Bytes([255]).to_text().is_none(): return panic(
        "invalid UTF8 accepted"
    )
    if "é".to_bytes().to_text() != some("é"): return panic("UTF8 roundtrip")

test "Bytes values direct bound and free calls return independent lists":
    let input = [0, 1, 255]
    let data = Bytes(values: input)
    input.with_value(index: 0, value: 42)
    let extract: fn() -> List[Int] = data.values
    if data.values() != [0, 1, 255] or extract() != values(data: data): return panic(
        "byte extraction or constructor changed"
    )

    let direct = data.values()
    let bound = extract()
    let free = values(data: data)
    direct.with_value(index: 0, value: 99)
    bound.append(12)
    free.reverse()
    if data.values() != [0, 1, 255] or extract() != [0, 1, 255]: return panic(
        "byte values alias receiver or another extraction"
    )

    let empty: List[Int] = []
    if Bytes(values: empty).values() != empty or Bytes([255]).values() != [255]: return panic(
        "empty or positional byte constructor"
    )

test "String slice clamp swap and strict bounds use Unicode scalars":
    let text = "aé🙂z"
    if text.slice(start: -2, end: 10) != "🙂z": return panic("relative clamped slice")
    if text.slice(start: -100, end: 100) != text: return panic("clamped extremes")
    if text.slice(start: 3, end: 1) != "": return panic("inverted slice")
    if text.substring(start: 3, end: 1) != "é🙂": return panic("swapped substring")
    if text.substring(start: -2, end: 2) != "aé": return panic("negative substring")
    if text.substring(start: 100, end: -100) != text: return panic("clamp then swap")
    if text.index_of("🙂") != some(2) or text.last_index_of("") != some(4): return panic(
        "scalar search offsets"
    )

    let invalid: Result[String, StringError] = error(StringError.OutOfRange)
    if text.slice_scalars(start: -2, end: 4) != invalid: return panic("strict negative")
    if text.slice_scalars(start: 1, end: 10) != invalid: return panic("strict end")
    if text.slice_scalars(start: 3, end: 1) != invalid: return panic("strict inverted")
    if value(text.slice_scalars(start: 4, end: 4)) != "": return panic(
        "empty strict end"
    )

test "string and bytes builders freeze idempotently":
    let text = StringBuilder()
    text.append("é")
    text.append("🙂")
    if text.freeze() != "é🙂" or text.freeze() != "é🙂": return panic("string freeze")

    let bytes = BytesBuilder()
    bytes.append(0)
    bytes.concat(Bytes([255, 1]))
    if (
        bytes.freeze() != Bytes([0, 255, 1])
        or bytes.freeze() != Bytes([0, 255, 1])
    ): return panic("bytes freeze")

test "empty text splits into one part and case mapping is full Unicode":
    if "".split(separator: ",") != [""]: return panic("empty split")

    let none_requested: List[String] = []
    if "".split(separator: "") != none_requested: return panic(
        "empty text has no scalars"
    )
    if "".split(separator: ",", max_parts: 0) != none_requested: return panic(
        "zero parts"
    )
    if "ß".upper() != "SS": return panic("sharp s upper")
    if "ﬁ".upper() != "FI": return panic("ligature upper")
    if "ΑΣ".lower() != "ας": return panic("final sigma")
    if "İ".lower() != "i\u{307}": return panic("dotted capital I")
    if "Maße".upper() != "MASSE": return panic("upper mixed")
