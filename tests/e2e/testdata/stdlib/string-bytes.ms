import {expect_equal, expect_false, expect_ok, expect_true} from "@std/testing.ms"
import {from_scalars, StringError, StringBuilder} from "@std/string.ms"
import {Bytes, BytesBuilder, values} from "@std/bytes.ms"

test "Unicode scalar indexing differs from byte length":
    let text = "aé🙂"
    (text.byte_length() != 7 or text.scalar_length() != 3) | try expect_false
    text.scalar_values() | try expect_equal(expected: [97, 233, 128578])
    (text.at(-1) != some("🙂") or text.scalar_at(1) != some(233)) | try expect_false
    (text.at(3).is_none()) | try expect_true
    from_scalars(text.scalar_values()) | try expect_ok | try expect_equal(
        expected: text
    )
    text.slice_scalars(start: 1, end: 3) | try expect_ok | try expect_equal(
        expected: "é🙂"
    )
    "é".normalize(form: "NFC") | try expect_ok | try expect_equal(expected: "é")

test "strings honor omitted none zero and explicit output limits":
    "ab".repeat(count: 2) | try expect_ok | try expect_equal(expected: "abab")
    "ab".repeat(count: 2) | try expect_ok | try expect_equal(expected: "abab")
    "ab".repeat(count: 0, max_bytes: 0) | try expect_ok | try expect_equal(expected: "")
    let limited: Result[String, StringError] = error(StringError.LimitExceeded)
    "é".repeat(count: 2, max_bytes: 3) | try expect_equal(expected: limited)
    "x".pad_start(target_length: 3, padding: "ab") | try expect_ok | try expect_equal(
        expected: "abx"
    )
    "x".pad_end(target_length: 3, padding: "ab") | try expect_ok | try expect_equal(
        expected: "xab"
    )
    "ab".repeat(count: 4611686018427387904) | try expect_equal(expected: limited)
    "ab".pad_start(target_length: 9223372036854775807, padding: "x") | try expect_equal(
        expected: limited
    )
    try expect_false(
        (
            "ab".pad_end(
                target_length: 4611686018427387904,
                padding: "xyz",
                max_bytes: 9223372036854775807
            ) != limited
        )
    )
    "aa".replace_all(old: "a", new: "xy") | try expect_ok | try expect_equal(
        expected: "xyxy"
    )
    "a,,b".split(separator: ",", max_parts: 2) | try expect_equal(expected: ["a", ""])
    " \té \n".trim() | try expect_equal(expected: "é")
    let invalid: Result[String, StringError] = error(StringError.InvalidInput)
    "a".normalize(form: "invalid") | try expect_equal(expected: invalid)
    let scalar_error: Result[String, StringError] = error(StringError.InvalidInput)
    from_scalars([55296]) | try expect_equal(expected: scalar_error)

test "bytes copy slice search and UTF8 validation":
    let data = Bytes([0, 1, 255, 1])
    data.at(-1) | try expect_equal(expected: some(1))
    (data.at(4).is_none()) | try expect_true
    data.index_of(Bytes([1])) | try expect_equal(expected: some(1))
    data.last_index_of(Bytes([1])) | try expect_equal(expected: some(3))
    data.slice(start: 1, end: 3).unwrap() | try expect_equal(expected: Bytes([1, 255]))
    (
        data.slice(start: -3, end: -1).unwrap() | try expect_equal(
            expected: Bytes([1, 255])
        )
    )
    let byte_range: Result[Bytes, CollectionError] = error(CollectionError.OutOfRange)
    data.slice(start: 1, end: 10) | try expect_equal(expected: byte_range)
    data.slice(start: -10, end: 2) | try expect_equal(expected: byte_range)
    data.reversed() | try expect_equal(expected: Bytes([1, 255, 1, 0]))
    let copied = data.clone().with_value(index: 0, value: 42)
    (copied.at(0) != some(42) or data.at(0) != some(0)) | try expect_false
    (Bytes([255]).to_string().is_none()) | try expect_true
    "é".to_bytes().to_string() | try expect_equal(expected: some("é"))

test "Bytes values direct bound and free calls return independent lists":
    let input = [0, 1, 255]
    let data = Bytes(values: input)
    input.set(index: 0, value: 42)
    let extract: fn() -> List[Int] = data.values
    (data.values() != [0, 1, 255] or extract() != values(data: data)) | try expect_false
    let direct = data.values()
    let bound = extract()
    let free = values(data: data)
    direct.set(index: 0, value: 99)
    bound.append(12)
    free.reverse_in_place()
    (data.values() != [0, 1, 255] or extract() != [0, 1, 255]) | try expect_false
    let empty: List[Int] = []
    try expect_false(
        (
            Bytes(values: empty).values() != empty
            or Bytes([255]).values() != [255]
        )
    )

test "String slice uses Unicode scalars with relative bounds and OutOfRange errors":
    let text = "aé🙂z"
    let out_of_range: Result[String, StringError] = error(StringError.OutOfRange)
    text.slice(start: -2, end: 4) | try expect_ok | try expect_equal(expected: "🙂z")
    text.slice(start: 0, end: -1) | try expect_ok | try expect_equal(expected: "aé🙂")
    text.slice(start: 4, end: 4) | try expect_ok | try expect_equal(expected: "")
    text.slice(start: -2, end: 10) | try expect_equal(expected: out_of_range)
    text.slice(start: -100, end: 4) | try expect_equal(expected: out_of_range)
    text.slice(start: 3, end: 1) | try expect_equal(expected: out_of_range)
    (text.index_of("🙂") != some(2) or text.last_index_of("") != some(4)) | try expect_false
    let invalid: Result[String, StringError] = error(StringError.OutOfRange)
    text.slice_scalars(start: -2, end: 4) | try expect_equal(expected: invalid)
    text.slice_scalars(start: 1, end: 10) | try expect_equal(expected: invalid)
    text.slice_scalars(start: 3, end: 1) | try expect_equal(expected: invalid)
    text.slice_scalars(start: 4, end: 4) | try expect_ok | try expect_equal(
        expected: ""
    )

test "string and bytes builders freeze idempotently":
    let text = StringBuilder()
    text.append("é")
    text.append("🙂")
    (text.freeze() != "é🙂" or text.freeze() != "é🙂") | try expect_false
    let bytes = BytesBuilder()
    bytes.append(0)
    bytes.concat(Bytes([255, 1]))
    try expect_false(
        (
            bytes.freeze() != Bytes([0, 255, 1])
            or bytes.freeze() != Bytes([0, 255, 1])
        )
    )

test "empty text splits into one part and case mapping is full Unicode":
    "".split(separator: ",") | try expect_equal(expected: [""])
    let none_requested: List[String] = []
    "".split(separator: "") | try expect_equal(expected: none_requested)
    "".split(separator: ",", max_parts: 0) | try expect_equal(expected: none_requested)
    "ß".upper() | try expect_equal(expected: "SS")
    "ﬁ".upper() | try expect_equal(expected: "FI")
    "ΑΣ".lower() | try expect_equal(expected: "ας")
    "İ".lower() | try expect_equal(expected: "i\u{307}")
    "Maße".upper() | try expect_equal(expected: "MASSE")

test "indexing and slicing long mixed-width text matches scalar positions":
    let block = "aé€🙂"
    let text = (block.repeat(count: 600) | try expect_ok)
    text.length() | try expect_equal(expected: 2400)
    # Forward, backward and jumping reads of the same long text.
    var forward = 0
    var step = 0

    while step < 2400:
        forward = forward + text.scalar_at(step).unwrap()
        step = step + 1

    var backward = 0
    step = 2399

    while step >= 0:
        backward = backward + text.scalar_at(step).unwrap()
        step = step - 1

    (forward != 600 * (97 + 233 + 8364 + 128578) or backward != forward) | try expect_false
    try expect_false(
        (
            text.at(1200) != some("a")
            or text.at(2399) != some("🙂")
            or text.at(-2) != some("€")
        )
    )
    text.slice(start: 1199, end: 1203) | try expect_ok | try expect_equal(
        expected: "🙂aé€"
    )
    text.slice(start: 2396, end: 2400) | try expect_ok | try expect_equal(
        expected: block
    )
    text.slice(start: 0, end: 4) | try expect_ok | try expect_equal(expected: block)
    text.slice(start: 7, end: 7) | try expect_ok | try expect_equal(expected: "")
    text.slice_scalars(start: 1199, end: 1203) | try expect_ok | try expect_equal(
        expected: "🙂aé€"
    )
    text.slice_scalars(start: 2399, end: 2400) | try expect_ok | try expect_equal(
        expected: "🙂"
    )
    let out_of_range: Result[String, StringError] = error(cause: StringError.OutOfRange)
    text.slice_scalars(start: 2400, end: 2401) | try expect_equal(
        expected: out_of_range
    )
