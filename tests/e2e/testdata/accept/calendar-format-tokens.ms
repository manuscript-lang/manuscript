import (
	expect_equal from "@std/test/test.ms",
	timestamp from "@std/time.ms",
)

test "calendar format keeps token boundaries and literal text":
	moment := timestamp(1710073815, 250999999).get()
	expect_equal(moment.format("", "UTC").get(), "")?
	expect_equal(moment.format("literal", "UTC").get(), "literal")?
	expect_equal(
		moment.format("YYY M D H m s SS Z zon", "UTC").get(),
		"YYY M D H m s SS Z zon",
	)?
	expect_equal(
		moment.format(
			"YYYYYYYYYMMMMMDDDDHHHHmmmmssssSSSSSSSZZZZzonezone",
			"UTC",
		).get(),
		"20242024Y0303M1010121230301515250250S+00:00+00:00UTCUTC",
	)?
	expect_equal(
		moment.format("日付 YYYY 年 MM 月 DD 日 🕰 HH:mm:ss", "UTC").get(),
		"日付 2024 年 03 月 10 日 🕰 12:30:15",
	)?

	bad_zone: String! := error(Error("time: invalid input", kind: "EINVAL"))
	expect_equal(moment.format("", "Nowhere/City"), bad_zone)?
	expect_equal(moment.format("literal", "Nowhere/City"), bad_zone)?

test "calendar format retains minimum widths outside UTC year limits":
	first := timestamp(-62135596800, 0).get()
	last := timestamp(253402300799, 999999999).get()
	expect_equal(
		first.format("YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]", "-23:59").get(),
		"0000-12-31 00:01:00.000 -23:59 [-23:59]",
	)?
	expect_equal(
		last.format("YYYY-MM-DD HH:mm:ss.SSS ZZ [zone]", "+23:59").get(),
		"10000-01-01 23:58:59.999 +23:59 [+23:59]",
	)?
