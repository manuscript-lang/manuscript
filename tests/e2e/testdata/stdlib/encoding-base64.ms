import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	base64_decode, base64_encode from "@std/data/encoding.ms",
	expect_equal from "@std/test/test.ms",
)

test "empty Base64 accepts default and explicit alphabets":
	empty := Bytes([])
	expect_equal(base64_encode(empty), "")?
	expect_equal(base64_encode(empty, false), "")?
	expect_equal(base64_encode(empty, true), "")?

	view := Bytes([251, 255, 0]).slice(1, 1)?
	expect_equal(base64_encode(view), "")?
	expect_equal(base64_encode(view, true), "")?

test "Base64 after empty retains alphabets and padding tails":
	expect_equal(base64_encode(Bytes([])), "")?
	expect_equal(base64_encode(Bytes([251])), "+w==")?
	expect_equal(base64_encode(Bytes([251, 255])), "+/8=")?
	expect_equal(base64_encode(Bytes([251, 255, 0])), "+/8A")?
	expect_equal(base64_encode(Bytes([251]), true), "-w==")?
	expect_equal(base64_encode(Bytes([251, 255]), true), "-_8=")?
	expect_equal(base64_encode(Bytes([251, 255, 0]), true), "-_8A")?

test "Base64 encodes every byte and empty views":
	var out = BytesBuilder()
	for n in 0..256:
		out.append(n.to_uint8().get(0))

	data := out.build()
	expect_equal(
		base64_encode(data),
		"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w=="
	)?
	expect_equal(
		base64_encode(data, true),
		"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn-AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq-wsbKztLW2t7i5uru8vb6_wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t_g4eLj5OXm5-jp6uvs7e7v8PHy8_T19vf4-fr7_P3-_w=="
	)?

	empty := data.slice(127, 127)?
	expect_equal(base64_encode(empty), "")?
	expect_equal(base64_decode(base64_encode(data))?, data)?
	expect_equal(base64_decode(base64_encode(data, true), true)?, data)?

fn padded_input(length: Int) Bytes:
	var out = BytesBuilder()
	out.append(42)

	for i in 0..length:
		byte := if i % 3 == 0: 251 else: (if i % 3 == 1: 255 else: 0)
		out.append(byte.to_uint8().get(0))

	out.append(42)
	return out.build().slice(1, length + 1).get(Bytes([]))

test "Base64 preserves tails across small and batch boundaries":
	for length in [
		31, 32, 33, 34, 35, 12285, 12286, 12287, 12288, 12289, 12290, 12291, 24573,
		24574, 24575, 24576, 24577, 24578, 24579
	]:
		data := padded_input(length)
		expect_equal(data.length(), length)?

		tail := if length % 3 == 1: "+w==" else: (if length % 3 == 2: "+/8=" else: "")
		url_tail := if length % 3 == 1: "-w==" else: (
			if length % 3 == 2: "-_8=" else: ""
		)
		expect_equal(base64_encode(data), ("+/8A".repeat(length / 3)?) + tail)?
		expect_equal(base64_encode(data, true), ("-_8A".repeat(length / 3)?) + url_tail)?
