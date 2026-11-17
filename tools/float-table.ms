// Prints crates/ms-rt/src/float_table.rs, the powers of ten behind the shortest float
// digits:
//   ms run tools/float-table.ms > crates/ms-rt/src/float_table.rs
// `make repo-check` does not read it; the runtime test `shortest_digits_match_the_standard_formatter`
// fails when any entry is wrong.
import BigInt, from_int from "@std/math/math.ms"

// floor(log2(10^e)) for an exponent e of either sign.
fn floor_log2_pow10(e: Int) Int:
	ten := from_int(10)
	if e >= 0: return bit_length(ten.pow(e).get()) - 1

	// 10^e is 1 / N: floor(log2(1 / N)) is minus the bit length of N - 1.
	n := ten.pow(-e).get()
	return -bit_length(n.subtract(from_int(1)))

fn bit_length(value: BigInt) Int:
	return value.to_string_radix(2).length()

// g(k) = floor(10^-k * 2^(125 - floor(log2(10^-k)))) + 1, a 126-bit value.
fn entry(k: Int) BigInt:
	e := -k
	r := 125 - floor_log2_pow10(e)
	ten := from_int(10)

	if e >= 0:
		scaled := ten.pow(e).get()
		whole := if r >= 0: scaled.shift_left(r).get() else: scaled.shift_right(
			-r
		).get()
		return whole.add(from_int(1))

	whole := from_int(1).shift_left(r).get().divide(ten.pow(-e).get()).get()
	return whole.add(from_int(1))

fn hex16(value: BigInt) String:
	return f"0x{value.to_string_radix(16).pad_start(16, "0")}"

fn main() Void:
	mask := from_int(1).shift_left(63).get().subtract(from_int(1))
	print(
		"//! Generated table for `float_digits.rs`: for each decimal exponent `k` from -324 through 292,"
	)
	print(
		"//! `g(k) = floor(10^-k * 2^(125 - floor(log2(10^-k)))) + 1`, a 126-bit value split as"
	)
	print(
		"//! `(g >> 63, g & (2^63 - 1))`. Regenerate with `ms run tools/float-table.ms`."
	)
	print("")
	print("pub const K_MIN: i32 = -324;")
	print("")
	print("pub static G: [(u64, u64); 617] = [")

	for k in - 324..293:
		g := entry(k)
		print(f"    ({hex16(g.shift_right(63).get())}, {hex16(g.bit_and(mask))}),")

	print("];")
