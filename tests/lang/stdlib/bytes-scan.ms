// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

test "index_of_byte finds a byte at or after start" {
	data := Bytes([1, 2, 3, 2, 255])
	expect_equal(data.index_of_byte(2, 0), 1)?
	expect_equal(data.index_of_byte(2, 2), 3)?
	expect_equal(data.index_of_byte(255, 0), 4)?
	expect_equal(data.index_of_byte(9, 0), null)?
}

test "index_of_byte handles out-of-range arguments" {
	data := Bytes([1, 2])
	expect_equal(data.index_of_byte(1, -3), 0)?
	expect_equal(data.index_of_byte(1, 5), null)?
	expect_equal(data.index_of_byte(2, 2), null)?
	expect_equal(Bytes([]).index_of_byte(0, 0), null)?
}

test "decode_utf8_range decodes a byte range" {
	data := "aé€b".to_bytes()
	expect_equal(data.decode_utf8_range(0, data.length()), "aé€b")?
	expect_equal(data.decode_utf8_range(1, 3), "é")?
	expect_equal(data.decode_utf8_range(2, 3), null)?
	expect_equal(data.decode_utf8_range(2, 2), "")?
}

test "view borrows a range without copying" {
	data := Bytes([1, 2, 3, 4, 5])
	middle := data.view(1, 4)
	expect_equal(middle.length(), 3)?
	expect_equal(middle.get_or(0, null), 2)?
	expect_equal(data.view(-2, 5).clone(), Bytes([4, 5]))?
	expect_equal(data.view(2, 2).length(), 0)?

	kept := middle.clone()
	expect_equal(kept, Bytes([2, 3, 4]))?
}

test "view of a temporary is owned" {
	tail := "hello".to_bytes().view(1, 5)
	expect_equal(tail, "ello".to_bytes())?
}

test "view agrees with slice and equality compares the bytes" {
	data := "aé🙂z héllo wörld and a longer tail".to_bytes()
	n := data.length()
	var a = -n

	while a <= n {
		var b = a

		while b <= n {
			want := data.slice(a, b)

			if want.is_ok() {
				expect_equal(data.view(a, b).clone(), want.get())?
				expect_equal(data.view(a, b) == want.get(), true)?
			}

			b += 3
		}

		a += 4
	}

	expect_equal(data.view(1, 4) == data.view(1, 5), false)?
	expect_equal(data.view(0, 0) == Bytes([]), true)?
	expect_equal(Bytes([1, 2, 3]) == Bytes([1, 2, 4]), false)?
}

test "view_bytes borrows the text without copying" {
	short := "héy"
	long := "a longer text that does not fit inline, with é and 🙂 inside"
	expect_equal(short.view_bytes() == short.to_bytes(), true)?
	expect_equal(long.view_bytes() == long.to_bytes(), true)?
	expect_equal(long.view_bytes().view(2, 8).clone(), "longer".to_bytes())?
	expect_equal("".view_bytes().length(), 0)?
	expect_equal(long.view(0, 8).view_bytes().length(), 8)?

	kept := long.view_bytes().clone()
	expect_equal(kept, long.to_bytes())?
	expect_equal(
		long.view_bytes().index_of("é".to_bytes()),
		long.to_bytes().index_of("é".to_bytes()),
	)?
}

test "view_bytes of a temporary is owned" {
	bytes := "hello world".upper().view_bytes()
	expect_equal(bytes, "HELLO WORLD".to_bytes())?
}

test "view_bytes of short text survives later statements and blocks" {
	short := "héy"
	bytes := short.view_bytes()
	var total = 0

	for i in 0..4 {
		other := f"x{i}y".view_bytes()
		literal := "abc".view_bytes()

		if other.length() > 2 {
			total += other.length()
		} else {
			total += 1
		}

		expect_equal(literal.length(), 3)?
		expect_equal(bytes == short.to_bytes(), true)?
	}

	expect_equal(total, 12)?
	expect_equal(bytes.length(), 4)?
	expect_equal(bytes.view(1, 3).clone(), "é".to_bytes())?
}
// expect-exit: 0
// expect-tests: passed=9 failed=0
