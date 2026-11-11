// conform: tags=records,stdlib-json,testing
// conform: phase=test
import (
	parse, stringify from "@std/data/json.ms",
	expect_equal, expect_error from "@std/test/test.ms",
)

type Sized:
	small: UInt8
	signed: Int8
	wide: UInt64
	single: Float32
	maybe: UInt16?
	items: List[Int32]

fn sample() Sized:
	maybe: UInt16 := 7
	single: Float32 := 0.1
	low: Int32 := -1
	high: Int32 := 2
	return Sized(255, -128, 18446744073709551615, single, maybe, [low, high])

test "JSON writes sized numbers like Int and Float":
	expect_equal(
		stringify(sample()),
		ok(
			"\{\"small\":255,\"signed\":-128,\"wide\":18446744073709551615,\"single\":0.1,\"maybe\":7,\"items\":[-1,2]\}"
		)
	)?

test "JSON reads sized numbers back":
	text := stringify(sample()).get()
	back := parse[Sized](text).get()
	expect_equal(back.small.to_int(), 255)?
	expect_equal(back.signed.to_int(), -128)?
	expect_equal(back.wide.to_string_radix(16), "ffffffffffffffff")?
	expect_equal(stringify(back).get(), text)?

test "JSON rejects sized numbers outside their range":
	head := "\{\"signed\":0,\"wide\":0,\"single\":0,\"items\":[]"
	expect_equal(
		(expect_error(parse[Sized](head + ",\"small\":256\}"))?).kind, "EBADMSG"
	)?
	expect_equal(
		(expect_error(parse[Sized](head + ",\"small\":-1\}"))?).kind, "EBADMSG"
	)?
	expect_equal(
		(
			expect_error(
				parse[Sized](
					"\{\"small\":0,\"signed\":-129,\"wide\":0,\"single\":0,\"items\":[]\}"
				)
			)?
		).kind,
		"EBADMSG"
	)?
	expect_equal(
		(
			expect_error(
				parse[Sized](
					"\{\"small\":0,\"signed\":0,\"wide\":18446744073709551616,\"single\":0,\"items\":[]\}"
				)
			)?
		).kind,
		"EBADMSG"
	)?
	expect_equal(
		(
			expect_error(
				parse[Sized](
					"\{\"small\":0,\"signed\":0,\"wide\":-1,\"single\":0,\"items\":[]\}"
				)
			)?
		).kind,
		"EBADMSG"
	)?
	expect_equal(
		(
			expect_error(
				parse[Sized](
					"\{\"small\":0,\"signed\":0,\"wide\":0,\"single\":1e39,\"items\":[]\}"
				)
			)?
		).kind,
		"EBADMSG"
	)?
	expect_equal(
		(
			expect_error(
				parse[Sized](
					"\{\"small\":0,\"signed\":0,\"wide\":0,\"single\":0,\"items\":[2147483648]\}"
				)
			)?
		).kind,
		"EBADMSG"
	)?
