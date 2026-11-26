// conform: tags=lists,ownership
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Pile {
	n Int
	tags List[String]
}

type Shelf {
	pile Pile
	label String
}

test "a field of a list element is assigned where the element lies" {
	var piles = [Pile(1, ["a"]), Pile(2, ["b"])]
	piles[1].n = 7
	piles[0].tags = ["x", "y"]
	piles[0].n | expect_equal(1)?
	piles[1].n | expect_equal(7)?
	piles[0].tags | expect_equal(["x", "y"])?
	piles[1].tags | expect_equal(["b"])?
}

test "a nested field of a map entry is assigned where the entry lies" {
	var shelves = Map[String, Shelf]()
	shelves["k"] = Shelf(Pile(1, []), "one")
	shelves["k"].pile.n = 5
	shelves["k"].label = "five"
	shelves["k"].pile.n | expect_equal(5)?
	shelves["k"].label | expect_equal("five")?
}

test "a compound assignment into an element field updates it once" {
	var piles = [Pile(1, [])]
	piles[0].n += 4
	piles[0].n | expect_equal(5)?
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
