// conform: tags=testing,tier-io
// conform: phase=test
import (
	histogram from "@std/data/histogram.ms",
	infinity, nan from "@std/math/math.ms",
	expect_equal, expect_fault, expect_true from "@std/test/test.ms",
	milliseconds from "@std/time.ms",
)

test "histogram summarizes exact small values":
	var h = histogram()
	expect_true(h.minimum().is_none())?
	expect_true(h.percentile(50.0).is_none())?
	for value in 1..11: h.record(value)
	expect_equal(h.count(), 10)?
	expect_equal(h.minimum().get(0), 1)?
	expect_equal(h.maximum().get(0), 10)?
	expect_equal(h.mean(), 5.5)?
	expect_equal(h.percentile(50.0).get(0), 5)?
	expect_equal(h.percentile(100.0).get(0), 10)?
	expect_equal(h.percentile(0.0).get(0), 1)?

test "histogram buckets large values within three percent and caps at the maximum":
	var h = histogram()
	for value in 0..1000: h.record(1000000 + value * 1000)

	p99 := h.percentile(99.0).get(0)
	expect_true(p99 >= 1989000 and p99 <= 1999000 * 103 / 100)?
	expect_equal(h.percentile(100.0).get(0), 1999000)?
	h.reset()
	expect_equal(h.count(), 0)?

test "histogram times a span and returns its result":
	var h = histogram()
	answer := h.time(fn: 42)
	expect_equal(answer, 42)?
	expect_equal(h.count(), 1)?
	h.record_duration(milliseconds(2))
	expect_equal(h.maximum().get(0) >= 2000000, true)?

test "histogram answers for the highest valid Int bucket":
	var h = histogram()
	h.record(9223372036854775807)
	expect_equal(h.percentile(100.0).get(0), 9223372036854775807)?
	expect_equal(h.percentile(50.0).get(0), 9223372036854775807)?

	var low_edge = histogram()
	low_edge.record(9079256848778919936)
	expect_equal(low_edge.percentile(100.0).get(0), 9079256848778919936)?

fn discard_percentile(value: Int?) Unit:
	return unit

test "histogram rejects invalid percentiles whether empty or populated":
	var h = histogram()

	for populated in [false, true]:
		if populated: h.record(10)

		for p in [nan, -nan, infinity, -infinity, -0.1, 100.1]:
			message := expect_fault(fn: discard_percentile(h.percentile(p)))?
			expect_true(message.contains("must be within 0.0 and 100.0"))?

		for p in [-0.0, 0.0, 0.1, 50.0, 99.9, 100.0]:
			if populated:
				expect_equal(h.percentile(p), 10)?
			else:
				expect_true(h.percentile(p).is_none())?

		expect_equal(h.count(), if populated: 1 else: 0)?

test "histogram percentile returns the observation at an exact rank":
	for count in [25, 50]:
		var h = histogram()
		for value in 1..(count + 1):
			h.record(value)
		for p in [14, 28, 56]:
			expect_equal(h.percentile(p.to_float()), (p * count + 99) / 100)?

test "large observations keep an exact mean":
	var h = histogram()
	h.record(4611686018427387904)
	h.record(4611686018427387904)
	expect_equal(h.count(), 2)?
	expect_equal(h.mean(), 4611686018427387904.0)?
	h.record(9223372036854775807)
	expect_equal(h.maximum(), 9223372036854775807)?
	h.reset()
	h.record(10)
	h.record(20)
	expect_equal(h.mean(), 15.0)?
