// conform: tags=closures,control-flow,generics,modules,mutation,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/closures.ms
import expect_equal from "@std/test/test.ms"

fn apply(value: Int, action: fn(Int) Int) Int:
	return action(value)

fn countdown[T](value: T, count: Int) T:
	if count == 0: return value
	return countdown(value, count - 1)

test "closures borrow variables and returned closures copy":
	var offset = 1
	offset = 10

	action := fn(value: Int):
		return value + offset

	if true:
		var local = 20
		local = 30
		expect_equal(action(local), 40)?

	expect_equal(action(3), 13)?
	expect_equal(offset, 10)?
	expect_equal(countdown("ready", 4), "ready")?

	// A returned closure owns its captures, so it takes a `let` copy and
	// does not see later changes to the variable.
	base := offset
	factory := fn() fn(Int) Int:
		return fn inner:
			return inner + base
	nested := factory()
	offset = 100
	expect_equal(nested(1), 11)?
