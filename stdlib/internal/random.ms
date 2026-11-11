import (
	Bytes from "@std/bytes.ms",
	bit_and,
	bit_or,
	bit_xor,
	max_int,
	min_int,
	shift_left,
	shift_right_unsigned,
	wrapping_add,
	wrapping_subtract from "@std/math/math.ms",
)

// The operating system's entropy: exactly `count` bytes, `count` from 0 through 16 MiB.
export extern fn msstd_random_os_bytes(count: Int) Bytes!

export fn invalid_input() Error:
	return Error("random: invalid input", kind: "EINVAL")

// Returns an unbiased integer from `min` up to `min + width`, where `width` is the 64-bit pattern of a positive count.
// Draws big-endian bytes masked to the width's bit length and redraws those at or past the width.
fn draw_below(min: Int, width: Int) Int!:
	var bits = 0
	var rest = width

	while rest != 0:
		rest = shift_right_unsigned(rest, 1)
		bits += 1

	count := (bits + 7) / 8
	mask := shift_right_unsigned(255, count * 8 - bits)

	while true:
		data := try msstd_random_os_bytes(count)
		var n = 0

		for i in 0..count:
			var byte = data.get(i).to_int()
			if i == 0:
				byte = bit_and(byte, mask)
			n = bit_or(shift_left(n, 8), byte)

		// Unsigned comparison: flipping the sign bit orders the 64-bit patterns as signed Ints.
		if bit_xor(n, min_int) < bit_xor(width, min_int):
			return ok(wrapping_add(min, n))

	return ok(min)

// An integer at least `min` and below `max_exclusive` (below the largest Int when none).
export fn draw_int(min: Int, max_exclusive: Int?) Int!:
	max := max_exclusive.get(max_int)
	if min >= max: return error(invalid_input())

	return draw_below(min, wrapping_subtract(max, min))

// A version-4 UUID.
export fn draw_uuid() String!:
	data := try msstd_random_os_bytes(16)
	digits := "0123456789abcdef".chars()
	var out = ""

	for i in 0..16:
		var byte = data.get(i).to_int()
		if i == 6:
			byte = bit_or(bit_and(byte, 15), 64)
		if i == 8:
			byte = bit_or(bit_and(byte, 63), 128)
		if i == 4 or i == 6 or i == 8 or i == 10:
			out = "{out}-"
		out = "{out}{digits[byte / 16]}{digits[byte % 16]}"

	return ok(out)

// A Float at least 0.0 and below 1.0 with 53 random bits.
export fn draw_float() Float!:
	bits := try draw_below(0, shift_left(1, 53))
	return ok(bits.to_float() / 9007199254740992.0)

// `values` shuffled in place by a Fisher-Yates pass.
export fn draw_shuffle[T](values: List[T]) List[T]!:
	var out = values
	var index = out.length() - 1

	while index > 0:
		out.swap(index, try draw_below(0, index + 1))
		index -= 1

	return ok(out)

// A uniformly chosen item, or none for an empty list.
export fn draw_choice[T](values: List[T]) T?!:
	if values.is_empty(): return ok(none)

	at := try draw_below(0, values.length())
	return ok(values.get(at))
