// conform: tags=control-flow,faults,interpolation,lists,maps,match,modules,optional,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
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
