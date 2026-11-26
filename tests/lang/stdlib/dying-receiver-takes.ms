// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"

// A text edit or decode of a value that dies at the call reuses its buffer (`opt_bytetake`); a value that is still
// read afterwards, or viewed, keeps its own.

fn padded(word String, times Int) String {
	return "  " + word.repeat(times) + "  "
}

fn big_bytes(count Int) Bytes {
	var out = BytesBuilder()
	for index in 0..count {
		out.append((97 + index % 26).to_uint8() or 0)
	}
	return out.build()
}

fn invalid_bytes() Bytes {
	var out = BytesBuilder()
	out.append_bytes(big_bytes(40))
	out.append(255.to_uint8() or 0)
	return out.build()
}

test "trim, upper, lower and replace of a dying value" {
	text := padded("Ab", 10)
	expect_equal(text.trim(), "AbAbAbAbAbAbAbAbAbAb")?
	expect_equal(padded("Ab", 10).upper().length(), 24)?
	expect_equal(padded("Ab", 10).lower().trim(), "abababababababababab")?
	expect_equal(padded("xy", 20).replace("x", "z").trim(), "zyzyzyzyzyzyzyzyzyzyzyzyzyzyzyzyzyzyzyzy")?
}

test "a value read after the call keeps its bytes" {
	text := padded("Ab", 12)
	trimmed := text.trim()
	expect_equal(text.length(), 28)?
	expect_equal(trimmed.length(), 24)?
}

test "a view of the receiver stays valid" {
	text := padded("Ab", 12)
	part := text.view(2, 6)
	trimmed := text.trim()
	expect_equal(part, "AbAb")?
	expect_equal(trimmed.length(), 24)?
}

test "a take in a loop and on one branch" {
	var total = 0
	for round in 0..4 {
		text := padded("q", 20 + round)
		if round % 2 == 0 {
			total += text.trim().length()
		} else {
			total += text.length()
		}
	}
	expect_equal(total, 20 + 25 + 22 + 27)?
}

test "decode_utf8 of a dying buffer, long, short, invalid and viewed" {
	long := big_bytes(100).decode_utf8() or "bad"
	expect_equal(long.length(), 100)?
	short := big_bytes(5).decode_utf8() or "bad"
	expect_equal(short, "abcde")?
	expect_equal(invalid_bytes().decode_utf8() or "bad", "bad")?
	kept := big_bytes(30)
	first := kept.decode_utf8() or "bad"
	expect_equal(kept.length(), 30)?
	expect_equal(first.length(), 30)?
}
// expect-exit: 0
// expect-tests: passed=5 failed=0
