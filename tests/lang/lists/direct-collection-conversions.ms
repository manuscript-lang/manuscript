// conform: tags=closures,control-flow,faults,generics,interfaces,lists,maps,match,modules,mutation,optional,records,sets,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/direct-collection-conversions.ms
import (
	panic from "@std/core.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
)

fn append_generic[T](var values List[T?], value T) Void {
	values.append(value)
}

test "direct append preserves checked argument conversions" {
	var values List[Int?] = []
	values.append(7)
	append_generic(values, 8)
	values.append(null)
	expect_false(
		(values[0] or panic("called Optional.get() on null")) != 7 or (
			values[1]
			or panic("called Optional.get() on null")
		) != 8
	)?
	expect_false(not (values[2] == null))?

	var flags List[Bool?] = []
	flags.append(false)
	expect_false(
		(flags[0] == null) or (
			flags[0]
			or panic("called Optional.get() on null")
		)
	)?

	var units List[Void?] = []
	units.append(void)
	expect_false(units[0] == null)?

	inner Int? := null
	var nested List[Int??] = []
	nested.append(inner)
	expect_true(nested[0] == null)?

	var callbacks List[(fn(Int) Int)?] = []
	callbacks.append(value => value + 1)
	expect_equal((callbacks[0] or panic("called Optional.get() on null"))(7), 8)?

	var errors List[Error] = []
	errors.append(Error("failure"))
	expect_equal(errors[0].message, "failure")?

	var results List[Int!?] = []
	failed Int! := error(Error("failure"))
	results.append(failed)

	widened := results[0] or panic("called Optional.get() on null")
	expect_false(widened.is_ok())?
	expect_equal(widened.err().message, "failure")?
}

test "direct keyed calls preserve optional keys and values" {
	var values List[Int?] = []
	values.append(7)
	expect_false(not values.contains(7) or values.contains(8))?

	var entries = Map[Int?, Int?]()
	entries.add(7, 9)
	expect_false(
		not entries.contains(7) or (
			entries.get(7)
			or panic("called Optional.get() on null")
		) != 9
	)?
	entries.add(value: 10, key: 8)
	expect_equal(entries.get(8) or panic("called Optional.get() on null"), 10)?

	var keys = Set[Int?]()
	keys.add(7)
	keys.add(null)
	expect_false(
		(not keys.contains(7) or not keys.contains(null) or keys.length() != 2)
	)?
}

test "direct calls capture receiver and arguments in written order" {
	first List[Int?] := []
	second List[Int?] := []
	var receiver = first.clone()
	receiver.append(
		(
			match present(7) {
				value => {
					receiver = second.clone()
					value
				} null => 0
			}
		) + 0
	)
	expect_false(not first.is_empty() or not second.is_empty())?

	var entries = Map[Int, Int?]()
	var key = 1
	entries.add(
		key,
		(
			match present(7) {
				value => {
					key = 2
					value
				} null => 0
			}
		) + 0,
	)
	expect_false(
		(
			(entries.get(1) or panic("called Optional.get() on null")) != 7
			or entries.contains(2)
			or key != 2
		)
	)?
}

fn present[T](hold value T) &T? {
	return value
}
