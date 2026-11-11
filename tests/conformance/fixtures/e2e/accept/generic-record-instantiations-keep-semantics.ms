// conform: tags=generics,lists,modules,optional,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/generic-record-instantiations-keep-semantics.ms
import expect_true from "@std/test/test.ms"

type Box[T]:
	v: T
	n: Int

type Pair[A, B]:
	first: A
	second: B

fn wrap[T](value: T) Box[T]:
	return Box[T](v: value, n: 1)

fn unwrap[T](b: Box[T]) T:
	return b.v

fn bump(b: Box[Int]) Int:
	return b.v + b.n

test "generic records":
	a := Box[Int](v: 4, n: 2)
	expect_true((a.v == 4 and a.n == 2))?

	dyn := wrap(value: 7)
	expect_true((bump(b: dyn) == 8))?
	expect_true((unwrap(b: a) == 4))?

	s := Box[String](v: "hi", n: 0)
	expect_true((s.v == "hi" and unwrap(b: s) == "hi"))?

	nested := Box[Box[Int]](v: a.clone(), n: 3)
	expect_true((nested.v.v == 4 and nested.v == a))?

	items := Box[List[Int]](v: [1, 2, 3], n: 0)
	expect_true((items.v.length() == 3))?

	pair := Pair[Int, String](first: 1, second: "x")
	expect_true((pair.first == 1 and pair.second == "x"))?
	expect_true((Box[Int](v: 4, n: 2) == a))?
	expect_true((not (Box[Int](v: 5, n: 2) == a)))?

	o := Box[Int?](v: 3, n: 0)
	expect_true((o.v == 3))?
