import (
	infinity,
	max_float,
	max_int,
	min_float,
	min_int,
	nan,
	next_after
) from "@std/math/math.ms"

/*
Boundary values for numeric tests. Run a function over every value or pair these return and compare the result with an exact
reference such as `BigRat` or `BigInt`, which is how a missing overflow, sign or rounding case shows up.
Example: `for x in int_boundaries(): expect_equal(wrapping_add(x, 0), x)?`.
*/

// Returns the Int values where arithmetic changes behavior: zero, plus and minus one and two, powers of two and
// their neighbors up to 2^62, 2^31 and 2^32 edges, 10^18, and both extremes with their neighbors.
export fn int_boundaries() List[Int]:
	var values = [
		0, 1, -1, 2, -2, 3, 7, -7, 10, 255, 256, -128, -129, 127, 128, 32767, 32768,
		-32768, -32769, 65535, 65536, 2147483647, 2147483648, -2147483648, -2147483649,
		4294967295, 4294967296, 1000000000000000000, -1000000000000000000,
		4611686018427387904, 4611686018427387903, -4611686018427387904,
		-4611686018427387905, 9007199254740991, 9007199254740992, 9007199254740993,
		-9007199254740993, max_int, max_int - 1, max_int - 2, min_int, min_int + 1,
		min_int + 2
	]
	return values

// Returns the Float values where results change character: both zeros, plus and minus one, values near one,
// the halves and ties around integers, 2^53 and its neighbors, the Int range edges, the largest and smallest
// finite values, the subnormal range from its smallest to its largest value, both infinities, and NaN.
export fn float_boundaries() List[Float]:
	smallest_normal := 2.2250738585072014e-308
	largest_subnormal := next_after(smallest_normal, 0.0)
	return [
		0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 1.5, -1.5, 2.5, -2.5, 0.1, -0.1,
		0.9999999999999999, 1.0000000000000002, 4503599627370495.5, 4503599627370496.0,
		9007199254740991.0, 9007199254740992.0, 9007199254740994.0,
		9223372036854775808.0, -9223372036854775808.0, 9223372036854774784.0, 1e21,
		1e22, -1e22, max_float, -max_float, next_after(max_float, 0.0), smallest_normal,
		-smallest_normal, largest_subnormal, -largest_subnormal, min_float, -min_float,
		min_float * 2.0, 1e-300, infinity, -infinity, nan
	]

// Returns `float_boundaries` without NaN and the two infinities, for references that need an exact rational.
export fn finite_float_boundaries() List[Float]:
	return float_boundaries().filter(fn value: value.is_finite())
