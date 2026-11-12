// conform: tags=testing,lists,mutation,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn grid(n: Int) List[List[Int]]:
	var g = List[List[Int]]()
	var i = 0
	while i < n:
		var row = List[Int]()
		var j = 0
		while j < n:
			row.append(0)
			j += 1
		g.append(row)
		i += 1
	return g

test "a nested write changes one element and no other":
	var g = grid(3)
	g[1][2] = 7
	g[0][0] = g[1][2] + 1
	g[2][1] = g[0][0] + g[1][2]
	expect_equal(g[0], [8, 0, 0])?
	expect_equal(g[1], [0, 0, 7])?
	expect_equal(g[2], [0, 15, 0])?

test "a negative index counts from the end of both lists":
	var g = grid(3)
	g[-1][-1] = 5
	g[-3][-2] = 6
	expect_equal(g[2][2], 5)?
	expect_equal(g[0][1], 6)?

test "a write into a row that grew later keeps the new length":
	var g = grid(2)
	g[0].append(4)
	g[0][2] = 9
	expect_equal(g[0], [0, 0, 9])?
	expect_equal(g[1], [0, 0])?

test "an owned element is dropped and replaced in place":
	var names = List[List[String]]()
	names.append(["a", "b"])
	names.append(["c", "d"])
	names[1][0] = "x" + "y"
	names[0][1] = names[1][0] + "!"
	expect_equal(names[0], ["a", "xy!"])?
	expect_equal(names[1], ["xy", "d"])?

test "three levels and Float rows write through the same way":
	var cube = List[List[List[Float]]]()
	var plane = List[List[Float]]()
	plane.append([0.0, 1.0])
	plane.append([2.0, 3.0])
	cube.append(plane)
	cube[0][1][0] = 5.5
	expect_equal(cube[0][1], [5.5, 3.0])?
	expect_equal(cube[0][0], [0.0, 1.0])?
