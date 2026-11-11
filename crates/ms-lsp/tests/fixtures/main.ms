import (
	Iterator from "@std/core.ms",
	stdout from "@std/io/io.ms",
	expect_equal from "@std/test/test.ms",
)

// A point in the plane.
type Point:
	x: Int
	y: Int = 0

enum Shape:
	Circle(radius: Int)
	Square(side: Int)
	Empty

interface Named:
	fn label() String

impl Point:
	fn norm() Int:
		return self.x * self.x + self.y * self.y

impl Named for Point:
	fn label() String:
		return "point"

type Counter:
	n: Int

impl Iterator[Int] for Counter:
	var fn next() Int?:
		if self.n == 0: return none

		self.n -= 1
		return self.n

fn add(a: Int, b: Int) Int:
	total := a + b
	return total

fn area(shape: Shape) Int:
	match shape:
		Circle(r):
			return r * r * 3
		Square(s):
			return s * s
		_:
			return 0

fn describe(p: Point) String:
	n := p.norm()
	return "norm is {n} at {p.x}"

export fn main() Int:
	_p := Point(x: 1, y: 2)
	values := [1, 2, 3]
	for v in values:
		_ := say("{v}")
	for tick in Counter(n: 2):
		_ := say("{tick}")

	result := add(1, 2)
	return result

fn say(text: String) Result[Unit, Error]:
	stdout().write("{text}\n")?
	return stdout().flush()

test "addition":
	expect_equal(add(1, 2), 3)?
