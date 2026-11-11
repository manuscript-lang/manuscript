// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes, BytesBuilder, values from "@std/bytes.ms",
	StringBuilder, from_scalars from "@std/string.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

test "Unicode scalar indexing differs from byte length":
	text := "aé🙂"
	expect_false(text.byte_length() != 7 or text.scalar_length() != 3)?
	expect_equal(text.scalar_values(), [97, 233, 128578])?
	expect_false(text.get(-1) != "🙂" or text.scalar_at(1) != 233)?
	expect_equal(text.get(3, default: "none"), "none")?
	expect_equal((text.scalar_values() | from_scalars?), text)?
	expect_equal((text.slice_scalars(1, 3)?), "é🙂")?
	expect_equal(("é".normalize("NFC")?), "é")?

test "strings honor omitted none zero and explicit output limits":
	expect_equal(("ab".repeat(2)?), "abab")?
	expect_equal(("ab".repeat(2)?), "abab")?
	expect_equal(("ab".repeat(0, 0)?), "")?

	limited: String! := error(Error("string: limit exceeded", kind: "EOVERFLOW"))
	expect_equal("é".repeat(2, 3), limited)?
	expect_equal("x".pad_start(3, "ab"), "abx")?
	expect_equal("x".pad_end(3, "ab"), "xab")?
	expect_equal("ab".repeat(4611686018427387904), limited)?
	expect_equal("aa".replace("a", "xy"), "xyxy")?
	expect_equal("a,,b".split(",", 2), ["a", ""])?
	expect_equal(" \té \n".trim(), "é")?

	invalid: String! := error(Error("string: invalid input", kind: "EINVAL"))
	expect_equal("a".normalize("invalid"), invalid)?

	scalar_error: String! := error(Error("string: invalid input", kind: "EINVAL"))
	expect_equal(from_scalars([55296]), scalar_error)?

test "bytes copy slice search and UTF8 validation":
	data := Bytes([0, 1, 255, 1])
	expect_equal(data.get(-1), 1)?
	expect_equal(data.get(4, default: 7), 7)?
	expect_equal(data.index_of(Bytes([1])), 1)?
	expect_equal(data.last_index_of(Bytes([1])), 3)?
	expect_equal(data.slice(1, 3).get(), Bytes([1, 255]))?
	expect_equal(data.slice(-3, -1).get(), Bytes([1, 255]))?

	byte_range: Bytes! := error(Error("binary: value out of range", kind: "ERANGE"))
	expect_equal(data.slice(1, 10), byte_range)?
	expect_equal(data.slice(-10, 2), byte_range)?
	expect_equal(data.reversed(), Bytes([1, 255, 1, 0]))?

	copied := data.clone().with_value(0, 42)
	expect_false(copied.get(0) != 42 or data.get(0) != 0)?
	expect_false(Bytes([255]).decode_utf8().is_some())?
	expect_equal("é".to_bytes().decode_utf8(), "é")?

test "Bytes values direct bound and free calls return independent lists":
	var input: List[UInt8] = [0, 1, 255]
	data := Bytes(input.clone())
	input.set(0, 42)

	extract: fn() List[UInt8] := data.values
	expect_false(data.values() != [0, 1, 255] or extract() != values(data))?

	var direct = data.values()
	var bound = extract()
	var free = values(data)
	direct.set(0, 99)
	bound.append(12)
	free.reverse()
	expect_false(data.values() != [0, 1, 255] or extract() != [0, 1, 255])?

	empty: List[UInt8] := []
	expect_false(
		Bytes(empty.clone()).values() != empty or Bytes([255]).values() != [255]
	)?

test "String slice uses Unicode scalars with relative bounds and OutOfRange errors":
	text := "aé🙂z"
	out_of_range: String! := error(Error("string: value out of range", kind: "ERANGE"))
	expect_equal((text.slice(-2, 4)?), "🙂z")?
	expect_equal((text.slice(0, -1)?), "aé🙂")?
	expect_equal((text.slice(4, 4)?), "")?
	expect_equal(text.slice(-2, 10), out_of_range)?
	expect_equal(text.slice(-100, 4), out_of_range)?
	expect_equal(text.slice(3, 1), out_of_range)?
	expect_false(text.index_of("🙂") != 2 or text.last_index_of("") != 4)?

	invalid: String! := error(Error("string: value out of range", kind: "ERANGE"))
	expect_equal(text.slice_scalars(-2, 4), invalid)?
	expect_equal(text.slice_scalars(1, 10), invalid)?
	expect_equal(text.slice_scalars(3, 1), invalid)?
	expect_equal((text.slice_scalars(4, 4)?), "")?

test "string and bytes builders freeze":
	var text = StringBuilder()
	text.append("é")
	text.append("🙂")
	expect_equal(text.build(), "é🙂")?

	var bytes = BytesBuilder()
	bytes.append(0)
	bytes.append_bytes(Bytes([255, 1]))
	expect_equal(bytes.build(), Bytes([0, 255, 1]))?

test "empty text splits into one part and case mapping is full Unicode":
	expect_equal("".split(","), [""])?

	none_requested: List[String] := []
	expect_equal("".split(""), none_requested)?
	expect_equal("".split(",", 0), none_requested)?
	expect_equal("ß".upper(), "SS")?
	expect_equal("ﬁ".upper(), "FI")?
	expect_equal("ΑΣ".lower(), "ας")?
	expect_equal("İ".lower(), "i\u{307}")?
	expect_equal("Maße".upper(), "MASSE")?

test "scalar reads alternating between long strings match grouped reads":
	a := "aé€🙂".repeat(300)?
	b := "日é".repeat(450)?
	c := "🙂x".repeat(450)?
	var alternating = 0
	for step in 0..900:
		alternating += a.scalar_at(step) + b.scalar_at(step) + c.scalar_at(899 - step)

	var grouped = 0
	for step in 0..900:
		grouped += a.scalar_at(step)
	for step in 0..900:
		grouped += b.scalar_at(step)
	for step in 0..900:
		grouped += c.scalar_at(899 - step)
	expect_equal(alternating, grouped)?
	expect_equal(a.scalar_at(-1), 128578)?
	expect_equal(b.scalar_at(-1), 233)?

test "indexing and slicing long mixed-width text matches scalar positions":
	block := "aé€🙂"
	text := block.repeat(600)?
	expect_equal(text.length(), 2400)?

	// Forward, backward and jumping reads of the same long text.
	var forward = 0
	for step in 0..2400:
		forward += text.scalar_at(step)

	var backward = 0
	for step in 0..2400:
		backward += text.scalar_at(2399 - step)
	expect_false(forward != 600 * (97 + 233 + 8364 + 128578) or backward != forward)?
	expect_false(
		(text.get(1200) != "a" or text.get(2399) != "🙂" or text.get(-2) != "€")
	)?
	expect_equal((text.slice(1199, 1203)?), "🙂aé€")?
	expect_equal((text.slice(2396, 2400)?), block)?
	expect_equal((text.slice(0, 4)?), block)?
	expect_equal((text.slice(7, 7)?), "")?
	expect_equal((text.slice_scalars(1199, 1203)?), "🙂aé€")?
	expect_equal((text.slice_scalars(2399, 2400)?), "🙂")?

	out_of_range: String! := error(Error("string: value out of range", kind: "ERANGE"))
	expect_equal(text.slice_scalars(2400, 2401), out_of_range)?

test "builder appends literals of every short length across growth":
	var sb = StringBuilder()

	for i in 0..40:
		sb.append("a")
		sb.append("bc")
		sb.append("def")
		sb.append("ghij")
		sb.append("klmno")
		sb.append("pqrstuv")
		sb.append("wxyzABCD")
		sb.append("EFGHIJKLMNOPQRS")
		sb.append("0123456789abcdef")
		sb.append("é€")

	one := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRS0123456789abcdefé€"
	var want = StringBuilder()
	for i in 0..40:
		want.append(one)
	expect_equal(sb.build(), want.build())?

test "builder appends variable text of every length across growth":
	base := "0123456789abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz"
	var sb = StringBuilder()
	var want = 0

	for round in 0..3:
		for n in 0..70:
			piece := base.slice(0, n)?
			sb.append(piece)
			want += n

	built := sb.build()
	expect_equal(built.byte_length(), want)?
	expect_equal((built.slice(0, 10)?), "0010120123")?

test "search indexes count scalars for ascii, inline and unicode text":
	long := "a".repeat(100).get().concat("!").concat("é").concat("!")
	expect_equal(long.index_of("!").get(-1), 100)?
	expect_equal(long.last_index_of("!").get(-1), 102)?

	ascii := "a".repeat(100).get().concat("!")
	expect_equal(ascii.index_of("!").get(-1), 100)?
	expect_equal(ascii.last_index_of("!").get(-1), 100)?
	expect_equal(ascii.last_index_of("a").get(-1), 99)?
	expect_equal("ab!".last_index_of("!").get(-1), 2)?
	expect_equal("é!".last_index_of("!").get(-1), 1)?
	expect_equal(ascii.last_index_of("?").get(-1), -1)?

test "count matches split for nonempty parts and counts scalars plus one for an empty part":
	expect_equal("word,".repeat(10000).get().count(","), 10000)?
	expect_equal("aaaa".count("aa"), 2)?
	expect_equal("héllo".count(""), 6)?
	expect_equal("".count("a"), 0)?
	expect_equal("".count(""), 1)?
	expect_equal("🙂x🙂".count("🙂"), 2)?
	expect_equal("abc".count("abcd"), 0)?
