// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_equal, expect_false, expect_fault, expect_true from "@std/test/test.ms",
)

fn every[T](values: List[T], predicate: fn(T) Bool) Bool:
	return values.all(fn value: predicate(value))

fn every_value[T](values: Map[String, T], predicate: fn(T) Bool) Bool:
	return values.all(fn key, value: predicate(value))

fn nested[T](value: T, predicate: fn(T) Bool) Bool:
	outer := fn:
		inner := fn(item: T) Bool: predicate(item)
		return inner(value)

	return outer()

fn defaulted[T](fallback: T, supplied: T, equal: fn(T, T) Bool) Bool:
	choose := fn(value: T = fallback) Bool: equal(value, fallback)
	omitted := choose()
	supplied_result := choose(supplied)
	required: fn(T) Bool := choose
	return omitted and supplied_result and required(supplied)

fn same_optional(left: Int?, right: Int?) Bool:
	if left == null: return right == null
	if right == null: return false

	return left == right

fn optional_default(value: Int? = 7) Int: value or (-1)

fn bound_missing[T: Clonable](cause: Error, value: T?) T!Error:
	convert := value.ok_or[Error]
	return convert(cause)

fn nested_bound_missing[T: Clonable](cause: Error, value: T?) T!Error:
	convert := fn:
		bound := value.ok_or[Error]
		return bound(cause.clone())

	return convert()

type Defaults:
	base: Int

fn Defaults.optional(value: Int? = self.base) Int: value or (-1)

test "generic callbacks preserve Optional inputs and present zero":
	values: List[Int?] := [null, 0, 4]
	expect_true(every(values, fn value: (value == null) or value >= 0))?
	expect_false(every(values, fn value: value == null))?
	expect_true(
		every_value(
			{"missing": null, "zero": 0},
			fn(value: Int?): ((value == null) or value == 0)
		)
	)?

test "generic callbacks see a nested Optional input as one layer":
	absent: Int?? := null
	inner_absent: Int? := null
	present_absent: Int?? := inner_absent
	inner_zero: Int? := 0
	present_zero: Int?? := inner_zero
	expect_true(every([absent], fn value: value == null))?
	expect_true(every([present_absent], fn value: value == null))?
	expect_true(every([present_zero], fn value: ((value != null) and value == 0)))?

test "generic callbacks keep Optional inputs through nested closures":
	value: Int? := null
	zero: Int? := 0
	expect_true(nested(value, fn item: item == null))?
	expect_true(nested(zero, fn item: (item != null) and item == 0))?

test "generic closure defaults and explicit callable arguments keep their behavior":
	expect_true(defaulted(7, 7, fn left, right: left == right))?
	expect_true(defaulted("seven", "seven", fn left, right: left == right))?

	present: Int? := 7
	absent: Int? := null
	expect_true(defaulted(present, present, same_optional))?
	expect_true(defaulted(absent, absent, same_optional))?

test "Optional closure defaults distinguish omitted and explicitly absent values":
	choose := fn(value: Int? = 7) Int: value or (-1)
	expect_equal(choose(), 7)?
	expect_equal(choose(null), -1)?
	expect_equal(choose(0), 0)?

	required: fn(Int?) Int := choose
	expect_equal(required(null), -1)?

test "named and bound Optional defaults distinguish omitted and absent arguments":
	named := optional_default
	expect_equal(named(), 7)?
	expect_equal(named(null), -1)?

	typed: fn(Int?) Int := named
	expect_equal(typed(null), -1)?

	defaults := Defaults(9)
	bound := defaults.optional
	expect_equal(bound(), 9)?
	expect_equal(bound(null), -1)?
	expect_equal(bound(0), 0)?

test "implicit Optional lambda defaults remain callable through inferred and explicit types":
	implicit := fn(value: Int?) Bool: value == null
	expect_true(implicit())?
	expect_true(implicit(null))?
	expect_false(implicit(0))?

	required: fn(Int?) Bool := implicit
	expect_true(required(null))?

test "bound native Optional arguments stay required after explicit function typing":
	values := [3, 4]
	get := values.get_or
	expect_equal(get(0), 3)?
	expect_equal(get(9, 7), 7)?

	required: fn(Int, Int?) Int := get
	expect_equal(required(1, null), 4)?
	expect_equal(required(9, 0), 0)?

test "generic native folds accept Optional accumulators without omission wrappers":
	values := {"one": 1, "two": 2}
	initial: Int? := null
	sum := values.fold_right(initial, fn acc, key, value: (acc or 0) + value)
	expect_equal(sum or panic("called Optional.get() on null"), 3)?

	fold := values.fold_right[Int?]
	bound_sum := fold(initial, fn acc, key, value: (acc or 0) + value)
	expect_equal(bound_sum or panic("called Optional.get() on null"), 3)?

	set := Set([1, 2])
	set_sum := set.fold_right(initial, fn acc, value: (acc or 0) + value)
	expect_equal(set_sum or panic("called Optional.get() on null"), 3)?

	fold_set := set.fold_right[Int?]
	bound_set_sum := fold_set(initial, fn acc, value: (acc or 0) + value)
	expect_equal(bound_set_sum or panic("called Optional.get() on null"), 3)?

test "bound generic native defaults preserve concrete and Optional payload types":
	missing: Int? := null
	text := missing.ok_or[String]
	expect_equal(text("absent").err(), "absent")?

	number := missing.ok_or[Int]
	expect_equal(number(0).err(), 0)?

	nested := missing.ok_or[Int?]
	absent: Int? := null
	expect_true(nested(absent).err() == null)?

	present: Int? := 0
	expect_equal(nested(present).err() or panic("called Optional.get() on null"), 0)?

test "bound Error causes are supplied at each call":
	missing: Int? := null
	direct := ok_or(missing, Error("direct"))
	expect_equal(direct.err().message, "direct")?

	convert := missing.ok_or[Error]
	expect_equal(convert(Error("first")).err().message, "first")?
	expect_equal(convert(Error("second")).err().message, "second")?
	expect_equal(bound_missing(Error("generic"), missing).err().message, "generic")?
	expect_equal(nested_bound_missing(Error("nested"), missing).err().message, "nested")?

	present: Int? := 0
	keep := present.ok_or[Error]
	expect_equal(keep(Error("unused")).get(), 0)?
	expect_equal(bound_missing(Error("unused"), present).get(), 0)?
	expect_equal(nested_bound_missing(Error("unused"), present).get(), 0)?

	text: String? := "present"
	expect_equal(bound_missing(Error("unused"), text).get(), "present")?
	expect_equal(nested_bound_missing(Error("unused"), text).get(), "present")?
