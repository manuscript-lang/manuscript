// conform: tags=generics,lists,modules,optional,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/default-type-arguments.ms
import expect_equal, expect_false from "@std/test/test.ms"

type Box[T, U = T]:
	first: T
	second: U

fn pick[T = Int](values: List[T]) Int:
	return values.length()

fn make[T = String]() T?:
	return none

fn pair[A, B = A](first: A, second: B) Box[A, B]:
	return Box[A, B](first, second)

test "omitted trailing type arguments use their defaults":
	same: Box[Int] := Box[Int](1, 2)
	mixed: Box[Int, String] := Box[Int, String](1, "x")
	expect_equal(same.second, 2)?
	expect_equal(mixed.second, "x")?

test "constructors fall back to defaults":
	b := Box[Int](3, 4)
	expect_equal(b.first + b.second, 7)?

test "calls infer first and only then use the default":
	inferred := make()
	expect_false(not (inferred.is_none()))?

	explicit: Int? := make()
	expect_false(not (explicit.is_none()))?
	expect_equal(pick([1, 2, 3]), 3)?
	expect_equal(pair(1, "a").second, "a")?
