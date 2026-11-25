// conform: tags=testing,tier-stdlib
// conform: phase=check
import max from "@std/math/math.ms"

type Point {
	x Int
}

export fn main() Int {
	furthest := max(Point(x: 1), Point(x: 2))
	return furthest.x
}
// expect-error: MS3000 10:17 Point does not satisfy Comparable; give Point the methods Comparable declares, or pass a type that already implements it
