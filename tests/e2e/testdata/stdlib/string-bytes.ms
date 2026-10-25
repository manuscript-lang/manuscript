from "@std/testing.ms" import expect_equal, expect_false
from "@std/collections.ms" import range
from "@std/string.ms" import from_scalars, StringError, StringBuilder
from "@std/bytes.ms" import Bytes, BytesBuilder, values

test "Unicode scalar indexing differs from byte length":
    let text = "aé🙂"
    try expect_false(text.byte_length() != 7 or text.scalar_length() != 3)
    try expect_equal(text.scalar_values(), [97, 233, 128578])
    try expect_false(text.get(-1) != "🙂" or text.scalar_at(1) != 233)
    try expect_equal(text.get(3, default: "none"), "none")
    try expect_equal((text.scalar_values() | from_scalars | try), text)
    try expect_equal((try text.slice_scalars(1, 3)), "é🙂")
    try expect_equal((try "é".normalize("NFC")), "é")

test "strings honor omitted none zero and explicit output limits":
    try expect_equal((try "ab".repeat(2)), "abab")
    try expect_equal((try "ab".repeat(2)), "abab")
    try expect_equal((try "ab".repeat(0, 0)), "")

    let limited: Result[String, StringError] = error(StringError.LimitExceeded)
    try expect_equal("é".repeat(2, 3), limited)
    try expect_equal("x".pad_start(3, "ab"), "abx")
    try expect_equal("x".pad_end(3, "ab"), "xab")
    try expect_equal("ab".repeat(4611686018427387904), limited)
    try expect_equal("aa".replace("a", "xy"), "xyxy")
    try expect_equal("a,,b".split(",", 2), ["a", ""])
    try expect_equal(" \té \n".trim(), "é")

    let invalid: Result[String, StringError] = error(StringError.InvalidInput)
    try expect_equal("a".normalize("invalid"), invalid)

    let scalar_error: Result[String, StringError] = error(StringError.InvalidInput)
    try expect_equal(from_scalars([55296]), scalar_error)

test "bytes copy slice search and UTF8 validation":
    let data = Bytes([0, 1, 255, 1])
    try expect_equal(data.get(-1), 1)
    try expect_equal(data.get(4, default: -1), -1)
    try expect_equal(data.index_of(Bytes([1])), some(1))
    try expect_equal(data.last_index_of(Bytes([1])), some(3))
    try expect_equal(data.slice(1, 3).get(), Bytes([1, 255]))
    try expect_equal(data.slice(-3, -1).get(), Bytes([1, 255]))

    let byte_range: Result[Bytes, CollectionError] = error(CollectionError.OutOfRange)
    try expect_equal(data.slice(1, 10), byte_range)
    try expect_equal(data.slice(-10, 2), byte_range)
    try expect_equal(data.reversed(), Bytes([1, 255, 1, 0]))

    let copied = data.clone().with_value(0, 42)
    try expect_false(copied.get(0) != 42 or data.get(0) != 0)
    try expect_false(not Bytes([255]).decode_utf8().is_none())
    try expect_equal("é".to_bytes().decode_utf8(), some("é"))

test "Bytes values direct bound and free calls return independent lists":
    var input = [0, 1, 255]
    let data = Bytes(input.clone())
    input.set(0, 42)

    let extract: Callable[[], List[Int]] = data.values
    try expect_false(data.values() != [0, 1, 255] or extract() != values(data))

    var direct = data.values()
    var bound = extract()
    var free = values(data)
    direct.set(0, 99)
    bound.append(12)
    free.reverse_in_place()
    try expect_false(data.values() != [0, 1, 255] or extract() != [0, 1, 255])

    let empty: List[Int] = []
    try expect_false(
        Bytes(empty.clone()).values() != empty or Bytes([255]).values() != [255]
    )

test "String slice uses Unicode scalars with relative bounds and OutOfRange errors":
    let text = "aé🙂z"
    let out_of_range: Result[String, StringError] = error(StringError.OutOfRange)
    try expect_equal((try text.slice(-2, 4)), "🙂z")
    try expect_equal((try text.slice(0, -1)), "aé🙂")
    try expect_equal((try text.slice(4, 4)), "")
    try expect_equal(text.slice(-2, 10), out_of_range)
    try expect_equal(text.slice(-100, 4), out_of_range)
    try expect_equal(text.slice(3, 1), out_of_range)
    try expect_false(text.index_of("🙂") != some(2) or text.last_index_of("") != some(4))

    let invalid: Result[String, StringError] = error(StringError.OutOfRange)
    try expect_equal(text.slice_scalars(-2, 4), invalid)
    try expect_equal(text.slice_scalars(1, 10), invalid)
    try expect_equal(text.slice_scalars(3, 1), invalid)
    try expect_equal((try text.slice_scalars(4, 4)), "")

test "string and bytes builders freeze":
    var text = StringBuilder()
    text.append("é")
    text.append("🙂")
    try expect_equal(text.build(), "é🙂")

    var bytes = BytesBuilder()
    bytes.append(0)
    bytes.append_bytes(Bytes([255, 1]))
    try expect_equal(bytes.build(), Bytes([0, 255, 1]))

test "empty text splits into one part and case mapping is full Unicode":
    try expect_equal("".split(","), [""])

    let none_requested: List[String] = []
    try expect_equal("".split(""), none_requested)
    try expect_equal("".split(",", 0), none_requested)
    try expect_equal("ß".upper(), "SS")
    try expect_equal("ﬁ".upper(), "FI")
    try expect_equal("ΑΣ".lower(), "ας")
    try expect_equal("İ".lower(), f"i\u{307}")
    try expect_equal("Maße".upper(), "MASSE")

test "indexing and slicing long mixed-width text matches scalar positions":
    let block = "aé€🙂"
    let text = try block.repeat(600)
    try expect_equal(text.length(), 2400)

    # Forward, backward and jumping reads of the same long text.
    var forward = 0
    for step in range(0, 2400):
        forward += text.scalar_at(step)

    var backward = 0
    for step in range(0, 2400):
        backward += text.scalar_at(2399 - step)
    try expect_false(forward != 600 * (97 + 233 + 8364 + 128578) or backward != forward)
    try expect_false(
        (text.get(1200) != "a" or text.get(2399) != "🙂" or text.get(-2) != "€")
    )
    try expect_equal((try text.slice(1199, 1203)), "🙂aé€")
    try expect_equal((try text.slice(2396, 2400)), block)
    try expect_equal((try text.slice(0, 4)), block)
    try expect_equal((try text.slice(7, 7)), "")
    try expect_equal((try text.slice_scalars(1199, 1203)), "🙂aé€")
    try expect_equal((try text.slice_scalars(2399, 2400)), "🙂")

    let out_of_range: Result[String, StringError] = error(StringError.OutOfRange)
    try expect_equal(text.slice_scalars(2400, 2401), out_of_range)
