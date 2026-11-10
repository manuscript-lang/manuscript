import expect_equal from "@std/test/test.ms"

type Options:
	harness: String
	tag: String

fn measure(name: String) Int?:
	return name.length()

fn owned_options(options: Options, oracle: Bool) Int:
	var local = options.clone()
	return measure(if oracle: "oracle" else: local.harness).get()

fn consumed_options(options: Options, oracle: Bool) Int:
	return measure(if oracle: "oracle" else: options.harness).get()

test "a conditional with a literal arm and a field arm can be a call argument":
	options := Options("abc", "t")
	try expect_equal(owned_options(options.clone(), false), 3)
	try expect_equal(owned_options(options.clone(), true), 6)
	try expect_equal(consumed_options(options.clone(), false), 3)
	try expect_equal(consumed_options(options, true), 6)
