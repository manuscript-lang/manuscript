import expect_equal from "@std/test/test.ms"

fn row[T](rows: List[List[T]], at: Int) List[T]:
	return rows[at]

fn first_row(rows: List[List[Int]]) List[Int]:
	return rows[0]

type Grid:
	rows: List[List[Int]]

impl Grid:
	fn first() List[Int]:
		return self.rows[0]

fn total(rows: List[List[Int]]) Int:
	var sum = row(rows, 0).sum()
	return sum

fn fresh_row() List[Int]:
	return [4, 5, 6]

test "borrowed helper iterables keep scalar and string elements in place":
	rows := [[1, 2], [3, 4]]
	var sum = first_row(rows).sum()
	expect_equal(sum, 3)?
	expect_equal(total(rows), 3)?
	sum = 0
	for value in rows[0]:
		sum += value
	expect_equal(sum, 3)?

	first := row(rows, 0)
	sum = 0
	for value in first:
		sum += value
	expect_equal(sum, 3)?
	expect_equal(rows[0], [1, 2])?

	words := [["a", "bb"]]
	var length = 0
	for word in row(words, 0):
		length += word.length()
	expect_equal(length, 3)?
	expect_equal(words[0], ["a", "bb"])?

test "borrowed receiver iterable handles break and continue":
	grid := Grid([[1, 2, 3, 4]])
	var sum = 0

	for value in grid.first():
		if value == 2: continue

		sum += value
		if value == 3: break

	expect_equal(sum, 4)?
	expect_equal(grid.rows[0], [1, 2, 3, 4])?

test "fresh results and temporary owners remain owned":
	var sum = fresh_row().sum()
	expect_equal(sum, 15)?
	sum = 0
	for value in row([[7, 8]], 0):
		sum += value
	expect_equal(sum, 15)?
