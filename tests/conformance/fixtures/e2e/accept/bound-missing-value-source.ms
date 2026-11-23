// conform: tags=testing
// conform: phase=test
import expect_equal, expect_fault, expect_true from "@std/test/test.ms"

fn generic_convert[T: Clonable](cause: Error, value: T?) T!Error:
	convert := value.ok_or[Error]
	return convert(cause)

fn ordinary(cause: Error? = null) Int!Error:
	return ok(if cause == null: 77 else: 88)

interface Convert:
	fn convert(cause: Error? = null) Int!Error

type Source:
	sentinel: Int

fn Source.convert(cause: Error? = null) Int!Error:
	return ok(if cause == null: self.sentinel else: 88)

// Exact expectations deliberately identify invocation lines, not binding lines.
test "bound ok_or takes its cause at each call":
	absent: Int? := null
	convert := absent.ok_or[Error]
	first_result := convert(Error("first"))
	second_result := convert(Error("second"))
	expect_equal(first_result.err().message, "first")?
	expect_equal(second_result.err().message, "second")?

test "immutable copies and captured native values keep their receiver":
	absent: Int? := null
	convert := absent.ok_or[Error]
	copied := convert
	copied_result := copied(Error("copied"))
	nested := fn:
		return copied(Error("nested"))
	nested_result := nested()
	expect_equal(copied_result.err().message, "copied")?
	expect_equal(nested_result.err().message, "nested")?

test "generic callers and direct calls supply their cause":
	absent: Int? := null
	expect_equal(generic_convert(Error("generic"), absent).err().message, "generic")?

	direct := ok_or(absent, Error("direct"))
	expect_equal(direct.err().message, "direct")?

	zero: Int? := 0
	text: String? := "present"
	expect_equal(generic_convert(Error("unused"), zero).get(), 0)?
	expect_equal(generic_convert(Error("unused"), text).get(), "present")?

test "ordinary callable and inherited defaults receive none":
	source := ordinary
	copied := source
	expect_equal(copied().get(), 77)?

	implementation := Source(77)
	inherited := implementation.convert
	expect_equal(inherited().get(), 77)?
	expect_equal(inherited(null).get(), 77)?

test "required joins preserve native behavior":
	zero: Int? := 0

	for flag in [true, false]:
		native_only := match flag:
			true: zero.ok_or[Error]
			false: zero.ok_or[Error]

		conditional := if flag: zero.ok_or[Error] else: zero.ok_or[Error]
		expect_equal(native_only(Error("unused")).get(), 0)?
		expect_equal(conditional(Error("unused")).get(), 0)?

test "nested Optional errors remain intact":
	absent: Int? := null
	convert := absent.ok_or[Error]
	supplied := ok_or(absent.clone(), Error("missing")).err()
	expect_equal(convert(supplied.clone()).err().message, supplied.message)?

	nested := absent.ok_or[Int?]
	inner_none: Int? := null
	expect_true(nested(inner_none).err() == null)?

	inner_zero: Int? := 0
	expect_equal(nested(inner_zero).err().get(), 0)?
