// conform: tags=closures,formatter,generics,modules,parser,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/inline-functions.ms
import expect_equal from "@std/test/test.ms"

type Transform:
	operation: fn(Int) Int

fn apply[T](operation: fn(T) T, value: T) T:
	return operation(value)

test "inline callbacks survive contextual rechecking":
	applied := apply(value: 3, fn value: return value + 1)
	expect_equal(applied, 4)?

	transform := Transform(fn value: return value + 2)
	expect_equal(transform.operation(3), 5)?
