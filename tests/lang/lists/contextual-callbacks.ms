// conform: tags=closures,control-flow,faults,generics,interfaces,lists,modules,optional,records,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/contextual-callbacks.ms
import expect_equal, expect_false from "@std/test/test.ms"

fn apply[T, U](value T, transform fn(T) U) U => transform(value)

fn chain[T, U](first fn() T, second fn(T) U) U => second(first())

fn with_result[T](transform fn() T!Error) T!Error => transform()

fn checked() Int!Error => ok(3)

type Box[T] {
	value T
}

type Callback[T, U] {
	transform fn(T) U
}

interface Read {
	fn get() Int
}

fn Box[Int].get() Int => self.value

fn invoke(transform (fn(Int) Int)?) Int {
	callback := transform
	if callback != null { return callback(4) }

	return 0
}

test "contextual callbacks and inline returns" {
	offset := 3
	strings := [1, 2, 3].filter(
		item => item > 1
	).map(number => (number + offset).to_string())
	expect_equal(strings.join(","), "5,6")?

	result := apply(transform: item => item + offset, value: 2)
	expect_equal(result, 5)?
	expect_equal(chain(second: item => item + 2, first: () => 3), 5)?

	callback := Callback(fn(item Int) => item + 1)
	expect_equal(callback.transform(3), 4)?

	view Read := Box(7)
	expect_equal(view.get(), 7)?
	expect_false(invoke() != 0 or invoke(item => item + 1) != 5)?

	functions List[fn(Int) Int] := [item => item + 4]
	expect_equal(functions[0](2), 6)?

	nested := fn(value Int) {
		inner := () => "text"
		return value + inner().scalar_length()
	}

	expect_equal(nested(2), 6)?

	success := with_result(() => ok(4))
	expect_equal(success, Result[Int, Error].ok(4))?

	propagated := with_result(
		() => {
			value := checked()?
			return ok(value + 2)
		}
	)

	expect_equal(propagated, Result[Int, Error].ok(5))?

	failed := with_result(
		() => {
			if true { return error(Error("expected")) } return ok(4)
		}
	)

	expect_equal(failed, Result[Int, Error].error(Error("expected")))?

	subtract fn(Int, Int) Int := (a, b) => a - b
	expect_equal(subtract(7, 2), 5)?

	defaulted fn(Int) Int := fn(item Int = 4) => item + 1
	expect_equal(defaulted(8), 9)?

	outer fn(Int) fn(Int) Int := base => {
		return extra => base + extra
	}
	expect_equal(outer(3)(4), 7)?
}
