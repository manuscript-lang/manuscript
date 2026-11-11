// conform: tags=control-flow,generics,modules,mutation,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/generic-instances.ms
import expect_equal, expect_false from "@std/test/test.ms"

type Point:
	x: Int

fn ident[T](x: T) T:
	return x

fn pick[T](first: Bool, left: T, right: T) T:
	chosen := if not first: right else: left
	return chosen

fn keep[T](value: T) T:
	copy := value
	return copy

fn count(value: Int) Int:
	return value + 1

test "parametric generics keep each instantiation's values":
	expect_equal(ident(41), 41)?
	expect_equal(ident(1.5), 1.5)?
	expect_equal(ident("go"), "go")?
	expect_false(not ident(true))?
	expect_equal(pick(first: true, left: 1, right: 2), 1)?
	expect_equal(pick(first: false, left: "a", right: "b"), "b")?
	expect_equal(keep(count(1)), 2)?

test "instances copy non-scalar arguments":
	point := Point(3)
	var same = ident(point).clone()
	same.x = 4
	expect_equal(same.x, 4)?
	expect_equal(point.x, 3)?

	var alias = pick(first: true, left: point.clone(), right: Point(9)).clone()
	alias.x = 5
	expect_equal(alias.x, 5)?
	expect_equal(point.x, 3)?
