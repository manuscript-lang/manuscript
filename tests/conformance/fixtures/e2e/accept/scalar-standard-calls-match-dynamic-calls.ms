// conform: tags=closures,control-flow,modules,mutation,numbers,stdlib-math,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/scalar-standard-calls-match-dynamic-calls.ms
import (
	atan2,
	ceil,
	floor,
	max,
	min,
	pow,
	remainder,
	round,
	sqrt,
	truncate from "@std/math/math.ms",
	expect_true from "@std/test/test.ms",
)

fn viaValue(f: fn(Float) Float, x: Float) Float: f(x)

test "typed math":
	expect_true((sqrt(value: 9.0) == 3.0))?
	expect_true((viaValue(f: sqrt, x: 16.0) == 4.0))?
	expect_true(
		(
			max(left: 0 - 2, right: 3) == 3
			and min(left: 0 - 2, right: 3) == 0 - 2
		)
	)?
	expect_true(((0.0 - 2.5).abs() == 2.5 and (0 - 7).abs() == 7))?
	expect_true(
		(
			floor(value: 2.7) == 2.0
			and ceil(value: 2.1) == 3.0
			and truncate(value: (0.0 - 2.7)) == 0.0 - 2.0
		)
	)?
	expect_true((round(value: 2.5) == 3.0 and round(value: 0.0 - 2.5) == 0.0 - 2.0))?
	expect_true((pow(base: 2.0, exponent: 10.0) == 1024.0))?
	expect_true(
		(
			min(left: 1.0, right: 2.0) == 1.0
			and max(left: 1.0, right: 2.0) == 2.0
		)
	)?
	expect_true((remainder(left: 7.0, right: 4.0) == 3.0))?
	expect_true((atan2(y: 0.0, x: 1.0) == 0.0))?
	expect_true((sqrt(value: 0.0 - 1.0).is_nan() and sqrt(value: 1.0).is_finite()))?

	var total = 0.0
	var i = 0

	while i < 4:
		total = total + sqrt(value: 4.0) + (0.0 - 1.0).abs()
		i += 1

	expect_true((total == 12.0))?

test "typed string members":
	text := "  Hello World  "
	expect_true((text.trim() == "Hello World"))?
	expect_true(
		(
			text.trim().upper() == "HELLO WORLD"
			and text.trim().lower() == "hello world"
		)
	)?
	expect_true((text.contains(value: "World") and not text.contains(value: "world")))?
	expect_true(
		(
			text.trim().starts_with(prefix: "Hello")
			and text.trim().ends_with(suffix: "World")
		)
	)?
