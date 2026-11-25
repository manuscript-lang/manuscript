// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn singleton(var values List[Int]) List[Int] {
	values.append(1)
	return values.clone()
}

fn bump(var values List[Int]) Void {
	values.append(1)
}

test "closure direct" {
	var values List[Int] = []
	callback := fn() List[Int] => singleton(values)
	_r := callback()
	values.length() | expect_equal(1)?
}

test "closure unit" {
	var values List[Int] = []
	callback := fn() Void => bump(values)
	callback()
	values.length() | expect_equal(1)?
}

test "closure append" {
	var values List[Int] = []
	callback := fn() Void => values.append(1)
	callback()
	values.length() | expect_equal(1)?
}

test "closure default passes a captured variable" {
	var values List[Int] = []
	callback := fn(value List[Int] = singleton(values)) Int => value.length()
	callback() | expect_equal(1)?
	values.length() | expect_equal(1)?
}
// expect-exit: 0
// expect-tests: passed=4 failed=0
