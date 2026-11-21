// Numbers and durations as the Rust command line prints them.
import expect_equal from "@std/test/test.ms"

// A duration the way Rust's `{:?}` prints it: `60s`, `1.5s`, `250ms`.
export fn debug_duration(total: Int) String:
	scales := [1000000000, 1000000, 1000, 1]
	names := ["s", "ms", "µs", "ns"]

	for at in 0..scales.length():
		scale := scales[at]
		if total < scale and scale > 1: continue

		whole := total / scale
		fraction := total % scale
		if fraction == 0: return f"{whole}{names[at]}"

		digits := f"{fraction}".pad_start(f"{scale}".length() - 1, "0")
		return f"{whole}.{digits.trim_end_chars("0")}{names[at]}"

	return f"{total}ns"

// A duration given in nanoseconds with a fitting unit: `12.300 ns`, `4.560 µs`.
export fn format_ns(nanos: Float) String:
	if nanos < 1000.0: return f"{nanos.to_fixed(3)} ns"
	if nanos < 1000000.0: return f"{(nanos / 1000.0).to_fixed(3)} µs"
	if nanos < 1000000000.0: return f"{(nanos / 1000000.0).to_fixed(3)} ms"

	return f"{(nanos / 1000000000.0).to_fixed(3)} s"

// A per-operation count: whole numbers print as integers, fractions with two decimals.
export fn round_count(value: Float) String:
	if whole := value.truncate_to_int():
		if whole.to_float() == value: return value.to_fixed(0)
	return value.to_fixed(2)

test "durations print the way the Rust command line prints them":
	expect_equal(debug_duration(60000000000), "60s")?
	expect_equal(debug_duration(1500000000), "1.5s")?
	expect_equal(debug_duration(250000000), "250ms")?
	expect_equal(debug_duration(2000000), "2ms")?
	expect_equal(debug_duration(1500), "1.5µs")?
	expect_equal(debug_duration(7), "7ns")?

test "statistics print the way the Rust command line prints them":
	expect_equal(format_ns(12.3), "12.300 ns")?
	expect_equal(format_ns(4560.0), "4.560 µs")?
	expect_equal(format_ns(7890000.0), "7.890 ms")?
	expect_equal(format_ns(1230000000.0), "1.230 s")?
	expect_equal(round_count(3.0), "3")?
	expect_equal(round_count(2.5), "2.50")?
