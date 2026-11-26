// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// Parts that a program changes, hands on or defaults are used where they lie: an
// element of a list inside a map entry, a field of an element, a payload of a `match`
// over an owner's last use, and a function value's omitted parameter.
type Note {
	id Int
	tags List[String]
}

type Pile {
	closed Bool
	notes List[Note]
	label String
}

fn parse(n Int) Int! {
	if n > 0 { return ok(n) }
	return error(Error("bad number"))
}

fn describe(n Int) String {
	parsed := parse(n)

	match parsed {
		ok(v) => {
			return f"ok {v}"
		}
		error(cause) => {
			return cause.message
		}
	}
}

test "a match over an owner's last use hands its payload on" {
	expect_equal(describe(4), "ok 4")?
	expect_equal(describe(0), "bad number")?
}

test "a list in a map entry changes where it lies" {
	var rows = Map[String, List[String]]()
	rows["a"] = ["x", "y"]
	rows["a"][1] = "z"
	rows["a"].append("w")
	rows["a"] | expect_equal(["x", "z", "w"])?

	var grid = Map[Int, List[List[Int]]]()
	grid[1] = [[1], [2]]
	grid[1][1].append(3)
	grid[1][0][0] = 9
	grid[1] | expect_equal([[9], [2, 3]])?
}

test "a field of a list element changes where it lies" {
	var pile = Pile(closed: false, notes: [Note(1, ["a"])], label: "first")
	pile.notes[0].tags.append("b")
	pile.notes[0].id = 7
	pile.label = "second"
	pile.notes[0].tags | expect_equal(["a", "b"])?
	pile.notes[0].id | expect_equal(7)?
	pile.label | expect_equal("second")?
}

test "a function value fills an omitted parameter without copying a given one" {
	label := fn(name String = "none") String => f"<{name}>"
	expect_equal(label(), "<none>")?
	expect_equal(label("given"), "<given>")?
	expect_equal(label(name: "named"), "<named>")?
}
// expect-exit: 0
// expect-tests: passed=4 failed=0
