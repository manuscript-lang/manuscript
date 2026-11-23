// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes, BytesBuilder, values from "@std/bytes.ms",
	from_scalars from "@std/string.ms",
	StringBuilder from "@std/string_builder.ms",
	expect_equal, expect_false from "@std/test/test.ms",
)

// Fails unless `result` is an error of `kind` whose message starts with `prefix`.
fn expect_failure(result: String!, kind: String, prefix: String) Void!:
	if value := result: return error(Error(f"expected {kind}, got ok({value})"))

	cause := result.err()
	expect_equal(cause.kind, kind)?
	expect_equal(cause.message.starts_with(prefix), true)?

test "Unicode scalar offsets differ from scalar count":
	text := "aé🙂"
	expect_false(text.length() != 7 or text.scalar_length() != 3)?
	expect_equal(text.scalar_values(), [97, 233, 128578])?
	expect_false(text.scalar_at(3, -1) != 128578 or text.scalar_at(1, -1) != 233)?
	expect_equal(text.scalar_at(2, -1), -1)?
	expect_equal(text.scalar_at(7, -1), -1)?
	expect_equal((text.scalar_values() | from_scalars?), text)?
	expect_equal(text.slice(1, 7), "é🙂")?
	expect_equal(("é".normalize("NFC")?), "é")?

test "repeat is plain text and clamps nonpositive counts":
	expect_equal("ab".repeat(2), "abab")?
	expect_equal("ab".repeat(0), "")?
	expect_equal("ab".repeat(-3), "")?
	expect_equal("".repeat(5), "")?
	expect_equal("x".pad_start(3, "ab"), "abx")?
	expect_equal("x".pad_end(3, "ab"), "xab")?
	expect_equal("aa".replace("a", "xy"), "xyxy")?
	expect_equal("a,,b".split(","), ["a", "", "b"])?
	expect_equal(" \té \n".trim(), "é")?

	invalid: String! := error(Error("string: invalid input", kind: "EINVAL"))
	expect_equal("a".normalize("invalid"), invalid)?

	scalar_error: String! := error(Error("string: invalid input", kind: "EINVAL"))
	expect_equal(from_scalars([55296]), scalar_error)?

test "bytes copy slice search and UTF8 validation":
	data := Bytes([0, 1, 255, 1])
	expect_equal(data.get(-1), 1)?
	expect_equal(data.get_or(4, default: 7), 7)?
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
	expect_false(Bytes([255]).decode_utf8() != null)?
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

test "String slice uses byte offsets with relative bounds and clamps out-of-range ones":
	text := "aé🙂z"
	expect_equal(text.slice(-5, 8), "🙂z")?
	expect_equal(text.slice(0, -1), "aé🙂")?
	expect_equal(text.slice(8, 8), "")?
	expect_equal(text.slice(-5, 10), "🙂z")?
	expect_equal(text.slice(-100, 8), "aé🙂z")?
	expect_equal(text.slice(3, 1), "")?
	expect_false(text.index_of("🙂") != 3 or text.last_index_of("") != 8)?
	expect_equal(text.slice(2, 8), "🙂z")?
	expect_equal(text.slice(1, 5), "é")?
	expect_equal(text.slice(0, 4), "aé")?
	expect_equal(text.slice(1, 3), "é")?

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
	expect_equal("ß".upper(), "SS")?
	expect_equal("ﬁ".upper(), "FI")?
	expect_equal("ΑΣ".lower(), "ας")?
	expect_equal("İ".lower(), "i\u{307}")?
	expect_equal("Maße".upper(), "MASSE")?

test "offset walks over long strings match scalar_values":
	a := "aé€🙂".repeat(300)
	b := "日é".repeat(450)

	for text in [a, b]:
		var walked = 0
		var offset = 0

		while offset < text.length():
			code := text.scalar_at(offset, -1)
			walked += code
			offset += (
				if code < 128: 1 else: if code < 2048: 2 else: if code < 65536: 3 else: 4
			)

		var total = 0
		for code in text.scalar_values():
			total += code
		expect_equal(walked, total)?
		expect_equal(text.scalar_at(text.length() - 1, -1), -1)?

test "offsets and slicing in long mixed-width text agree with the scalar walk":
	block := "aé€🙂"
	text := block.repeat(600)
	expect_equal(text.length(), 6000)?
	expect_equal(text.scalar_length(), 2400)?

	var forward = 0
	var offset = 0

	while offset < text.length():
		code := text.scalar_at(offset, -1)
		forward += code
		offset += (
			if code < 128: 1 else: if code < 2048: 2 else: if code < 65536: 3 else: 4
		)

	expect_equal(forward, 600 * (97 + 233 + 8364 + 128578))?
	expect_false(
		(
			text.scalar_at(3000, -1) != 97
			or text.scalar_at(5996, -1) != 128578
			or text.scalar_at(5993, -1) != 8364
		)
	)?
	expect_equal(text.slice(2996, 3006), "🙂aé€")?
	expect_equal(text.slice(5990, 6000), block)?
	expect_equal(text.slice(0, 10), block)?
	expect_equal(text.slice(6, 6), "")?
	expect_equal(text.slice(5996, 6000), "🙂")?
	expect_equal(text.slice(6000, 6001), "")?
	expect_equal(text.slice(7, 8), "")?

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
			piece := base.slice(0, n)
			sb.append(piece)
			want += n

	built := sb.build()
	expect_equal(built.length(), want)?
	expect_equal(built.slice(0, 10), "0010120123")?

test "search indexes are byte offsets for ascii, inline and unicode text":
	long := "a".repeat(100).concat("!").concat("é").concat("!")
	expect_equal(long.index_of("!") or (-1), 100)?
	expect_equal(long.last_index_of("!") or (-1), 103)?

	ascii := "a".repeat(100).concat("!")
	expect_equal(ascii.index_of("!") or (-1), 100)?
	expect_equal(ascii.last_index_of("!") or (-1), 100)?
	expect_equal(ascii.last_index_of("a") or (-1), 99)?
	expect_equal("ab!".last_index_of("!") or (-1), 2)?
	expect_equal("é!".last_index_of("!") or (-1), 2)?
	expect_equal(ascii.last_index_of("?") or (-1), -1)?

test "count matches split for nonempty parts and counts scalars plus one for an empty part":
	expect_equal("word,".repeat(10000).count(","), 10000)?
	expect_equal("aaaa".count("aa"), 2)?
	expect_equal("héllo".count(""), 6)?
	expect_equal("".count("a"), 0)?
	expect_equal("".count(""), 1)?
	expect_equal("🙂x🙂".count("🙂"), 2)?
	expect_equal("abc".count("abcd"), 0)?

test "list slice errors name the values that failed":
	items := [1, 2, 3]
	r := items.slice(1, 10)
	cause := r.err()
	expect_equal(
		cause.message.starts_with(
			"collection: value out of range: slice(1, 10) of a list with 3 items"
		),
		true,
	)?
