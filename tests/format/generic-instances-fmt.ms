// conform: tags=control-flow,formatter,generics,modules,mutation,parser,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/generic-instances.ms
import expect_equal, expect_false from "@std/test/test.ms"

type Point {
	x Int
}

fn ident[T](hold x T) &T {
	return x
}

fn pick[T](first Bool, move left T, move right T) T {
	chosen := if not first { right } else { left }
	return chosen
}

fn keep[T](hold value T) &T {
	copy := value
	return copy
}

fn count(value Int) Int {
	return value + 1
}

test "parametric generics keep each instantiation's values" {
	expect_equal(ident(41), 41)?
	expect_equal(ident(1.5), 1.5)?
	expect_equal(ident("go"), "go")?
	expect_false(not ident(true))?
	expect_equal(pick(first: true, left: 1, right: 2), 1)?
	expect_equal(pick(first: false, left: "a", right: "b"), "b")?
	expect_equal(keep(count(1)), 2)?
}

test "instances copy non-scalar arguments" {
	point := Point(3)
	var same = ident(point).clone()
	same.x = 4
	expect_equal(same.x, 4)?
	expect_equal(point.x, 3)?

	var alias = pick(first: true, left: point.clone(), right: Point(9)).clone()
	alias.x = 5
	expect_equal(alias.x, 5)?
	expect_equal(point.x, 3)?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: type Point {
// expect-formatted: \tx Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn ident[T](hold x T) &T {
// expect-formatted: \treturn x
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn pick[T](first Bool, move left, right T) T {
// expect-formatted: \tchosen := if not first { right } else { left }
// expect-formatted: \treturn chosen
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn keep[T](hold value T) &T {
// expect-formatted: \tcopy := value
// expect-formatted: \treturn copy
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn count(value Int) Int {
// expect-formatted: \treturn value + 1
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "parametric generics keep each instantiation's values" {
// expect-formatted: \texpect_equal(ident(41), 41)?
// expect-formatted: \texpect_equal(ident(1.5), 1.5)?
// expect-formatted: \texpect_equal(ident("go"), "go")?
// expect-formatted: \texpect_false(not ident(true))?
// expect-formatted: \texpect_equal(pick(first: true, left: 1, right: 2), 1)?
// expect-formatted: \texpect_equal(pick(first: false, left: "a", right: "b"), "b")?
// expect-formatted: \texpect_equal(keep(count(1)), 2)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "instances copy non-scalar arguments" {
// expect-formatted: \tpoint := Point(3)
// expect-formatted: \tvar same = ident(point).clone()
// expect-formatted: \tsame.x = 4
// expect-formatted: \texpect_equal(same.x, 4)?
// expect-formatted: \texpect_equal(point.x, 3)?
// expect-formatted:
// expect-formatted: \tvar alias = pick(first: true, left: point.clone(), right: Point(9)).clone()
// expect-formatted: \talias.x = 5
// expect-formatted: \texpect_equal(alias.x, 5)?
// expect-formatted: \texpect_equal(point.x, 3)?
// expect-formatted: }
