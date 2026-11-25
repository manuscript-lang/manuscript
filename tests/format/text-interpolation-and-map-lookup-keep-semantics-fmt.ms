// conform: tags=control-flow,faults,formatter,interpolation,lists,maps,match,modules,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/text-interpolation-and-map-lookup-keep-semantics.ms
import expect_true, fail from "@std/test/test.ms"

type Point {
	x Int
	y Int
}

fn halve(n Int) Int? {
	if n % 2 != 0 {
		return null
	}
	return (n / 2)
}

fn describe(key Point, m Map[Point, String]) String {
	match m.get(key: key) {
		v => {
			return f"found {v}"
		}
		null => {
			return "missing"
		}
	}
}

test "text interpolation" {
	n := 42
	f := 1.5
	ok := true
	s := "hi"
	expect_true((f"n={n} f={f} ok={ok} s={s}" == "n=42 f=1.5 ok=true s=hi"))?
	expect_true((f"{n}" == "42"))?
	expect_true((f"{s}{s}" == "hihi"))?
	expect_true(("".length() == 0))?
	expect_true((f"héllo {n}".scalar_length() == 8))?
	expect_true((f"{halve(n: 8)}" == f"{halve(n: 8)}"))?

	var items = List[Int]()
	items.append(value: 1)
	expect_true((f"{items}" == "[1]"))?
	expect_true((f"{Point(x: 1, y: 2)}".length() > 0))?
}

test "map lookup" {
	var m = Map[Int, Int]()
	m.add(key: 1, value: 10)

	match m.get(key: 1) {
		v => {
			expect_true((v == 10))?
		}
		null => {
			return fail("expected value")
		}
	}

	match m.get(key: 2) {
		v => {
			return fail(f"unexpected {v}")
		}
		null => {
			void
		}
	}

	var points = Map[Point, String]()
	points.add(key: Point(x: 1, y: 2), value: "a")
	expect_true((describe(key: Point(x: 1, y: 2), m: points) == "found a"))?
	expect_true((describe(key: Point(x: 2, y: 1), m: points) == "missing"))?
}
// expect-format: rewritten
// expect-formatted: import expect_true, fail from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: type Point {
// expect-formatted: \tx, y Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn halve(n Int) Int? {
// expect-formatted: \tif n % 2 != 0 {
// expect-formatted: \t\treturn null
// expect-formatted: \t}
// expect-formatted: \treturn (n / 2)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn describe(key Point, m Map[Point, String]) String {
// expect-formatted: \tmatch m.get(key: key) {
// expect-formatted: \t\tv => {
// expect-formatted: \t\t\treturn f"found {v}"
// expect-formatted: \t\t}
// expect-formatted: \t\tnull => {
// expect-formatted: \t\t\treturn "missing"
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "text interpolation" {
// expect-formatted: \tn := 42
// expect-formatted: \tf := 1.5
// expect-formatted: \tok := true
// expect-formatted: \ts := "hi"
// expect-formatted: \texpect_true((f"n={n} f={f} ok={ok} s={s}" == "n=42 f=1.5 ok=true s=hi"))?
// expect-formatted: \texpect_true((f"{n}" == "42"))?
// expect-formatted: \texpect_true((f"{s}{s}" == "hihi"))?
// expect-formatted: \texpect_true(("".length() == 0))?
// expect-formatted: \texpect_true((f"héllo {n}".scalar_length() == 8))?
// expect-formatted: \texpect_true((f"{halve(n: 8)}" == f"{halve(n: 8)}"))?
// expect-formatted:
// expect-formatted: \tvar items = List[Int]()
// expect-formatted: \titems.append(value: 1)
// expect-formatted: \texpect_true((f"{items}" == "[1]"))?
// expect-formatted: \texpect_true((f"{Point(x: 1, y: 2)}".length() > 0))?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "map lookup" {
// expect-formatted: \tvar m = Map[Int, Int]()
// expect-formatted: \tm.add(key: 1, value: 10)
// expect-formatted:
// expect-formatted: \tmatch m.get(key: 1) {
// expect-formatted: \t\tv => {
// expect-formatted: \t\t\texpect_true((v == 10))?
// expect-formatted: \t\t}
// expect-formatted: \t\tnull => {
// expect-formatted: \t\t\treturn fail("expected value")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tmatch m.get(key: 2) {
// expect-formatted: \t\tv => {
// expect-formatted: \t\t\treturn fail(f"unexpected {v}")
// expect-formatted: \t\t}
// expect-formatted: \t\tnull => {
// expect-formatted: \t\t\tvoid
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tvar points = Map[Point, String]()
// expect-formatted: \tpoints.add(key: Point(x: 1, y: 2), value: "a")
// expect-formatted: \texpect_true((describe(key: Point(x: 1, y: 2), m: points) == "found a"))?
// expect-formatted: \texpect_true((describe(key: Point(x: 2, y: 1), m: points) == "missing"))?
// expect-formatted: }
