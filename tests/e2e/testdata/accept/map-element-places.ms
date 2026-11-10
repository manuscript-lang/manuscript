import expect_contains, expect_equal, expect_fault from "@std/test/test.ms"

type Pile:
	n: Int
	tags: List[String]

test "a map entry takes a collection mutator in place":
	var m = Map[String, List[String]]()
	m["a"] = ["x"]
	m["a"].append("y")
	m["a"][0] = "z"
	m["a"] | try expect_equal(["z", "y"])

test "a map entry's record fields are assigned and mutated in place":
	var m = Map[String, Pile]()
	m["k"] = Pile(1, ["t"])
	m["k"].n = 7
	m["k"].tags.append("u")
	m["k"].n | try expect_equal(7)
	m["k"].tags | try expect_equal(["t", "u"])

test "map entries nest with list elements":
	var g = Map[Int, List[List[Int]]]()
	g[1] = [[1], [2]]
	g[1][1].append(3)
	g[1][0][0] = 9
	g[1] | try expect_equal([[9], [2, 3]])

test "changing a missing map entry faults like reading it":
	var m = Map[String, List[String]]()
	message := try expect_fault(
		fn:
			m["nope"].append("q")
	)
	message | try expect_contains("map key not found")
