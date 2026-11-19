// expect-mir: "move.out"
// expect-opt-mir-absent: "clone"
// A list element passed as `var` beside another `var` local moves out of its place, changes in
// the callee and moves back. It is not copied: copying a large element on every call made a
// JPEG decode quadratic in the image size.
type Plane:
	cells: List[Int]
	steps: Int

fn advance(var plane: Plane, var total: Int, at: Int) Void:
	plane.cells[at] = plane.cells[at] + 1
	plane.steps += 1
	total += plane.cells[at]

fn main() Void:
	var planes = [Plane([0].repeated(8), 0), Plane([0].repeated(8), 0)]
	var total = 0
	advance(planes[1], total, 3)
	print(f"{total} {planes[1].steps}")
