import expect_equal from "@std/test/test.ms"

type Options:
	continue: Bool
	type: String = "x"
	return: Int = 1

test "keywords are ordinary field names and members":
	options := Options(continue: true, return: 2)
	expect_equal(options.continue, true)?
	expect_equal(options.type, "x")?
	expect_equal(options.return, 2)?

	for i in [1, 2]:
		if i == 1: continue

		expect_equal(i, 2)?
