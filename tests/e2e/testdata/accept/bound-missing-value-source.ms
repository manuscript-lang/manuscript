import expect_equal, expect_true, expect_fault from "@std/test/test.ms"

fn generic_convert[T: Clonable](value: T?) T!Error:
	convert := value.ok_or[Error]
	return convert()

fn ordinary(cause: Error? = none) Int!Error:
	return ok(if cause.is_none(): 77 else: 88)

interface Convert:
	fn convert(cause: Error? = none) Int!Error

type Source:
	sentinel: Int

impl Convert for Source:
	fn convert(cause: Error?) Int!Error:
		return ok(if cause.is_none(): self.sentinel else: 88)

// Exact expectations deliberately identify invocation lines, not binding lines.
test "bound Error defaults use each invocation line":
	absent: Int? := none
	convert := absent.ok_or[Error]
	first_result := convert()
	second_result := convert()
	try expect_equal(
		first_result.err().message, "missing value at bound-missing-value-source.ms:24"
	)
	try expect_equal(
		second_result.err().message, "missing value at bound-missing-value-source.ms:25"
	)

test "immutable copies and captured native values keep invocation defaults":
	absent: Int? := none
	convert := absent.ok_or[Error]
	copied := convert
	copied_result := copied()
	nested := fn:
		return copied()
	nested_result := nested()
	try expect_equal(
		copied_result.err().message, "missing value at bound-missing-value-source.ms:37"
	)
	try expect_equal(
		nested_result.err().message, "missing value at bound-missing-value-source.ms:39"
	)

test "generic callers and direct calls keep their invocation lines":
	absent: Int? := none
	try expect_equal(
		generic_convert(absent).err().message,
		"missing value at bound-missing-value-source.ms:5"
	)

	direct := absent.ok_or()
	try expect_equal(
		direct.err().message, "missing value at bound-missing-value-source.ms:55"
	)

	zero: Int? := 0
	text: String? := "present"
	try expect_equal(generic_convert(zero).get(), 0)
	try expect_equal(generic_convert(text).get(), "present")

test "ordinary callable and inherited defaults receive none":
	source := ordinary
	copied := source
	try expect_equal(copied().get(), 77)

	implementation := Source(77)
	inherited := implementation.convert
	try expect_equal(inherited().get(), 77)
	try expect_equal(inherited(none).get(), 77)

test "required joins preserve native and source behavior with supplied none":
	zero: Int? := 0

	for flag in [true, false]:
		native_first := match flag:
			true: zero.ok_or[Error]
			false: ordinary

		source_first := match flag:
			true: ordinary
			false: zero.ok_or[Error]

		native_only := match flag:
			true: zero.ok_or[Error]
			false: zero.ok_or[Error]

		conditional := if flag: zero.ok_or[Error] else: ordinary
		try expect_equal(native_first(none).get(), if flag: 0 else: 77)
		try expect_equal(source_first(none).get(), if flag: 77 else: 0)
		try expect_equal(native_only(none).get(), 0)
		try expect_equal(conditional(none).get(), if flag: 0 else: 77)

test "supplied none remains supplied and nested Optional errors remain intact":
	absent: Int? := none
	convert := absent.ok_or[Error]
	bound_fault := try expect_fault(
		fn:
			_ignored := convert(none)
	)
	direct_fault := try expect_fault(
		fn:
			_ignored := absent.ok_or[Error](none)
	)
	try expect_true(bound_fault.contains("Optional.get() on none"))
	try expect_true(direct_fault.contains("Optional.get() on none"))

	supplied := absent.ok_or().err()
	try expect_equal(convert(supplied).err().message, supplied.message)

	nested := absent.ok_or[Int?]
	inner_none: Int? := none
	try expect_true(nested(inner_none).err().is_none())

	inner_zero: Int? := 0
	try expect_equal(nested(inner_zero).err().get(), 0)
