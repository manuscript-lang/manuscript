// conform: tags=strings,interpolation,records,tier-core
// conform: phase=run
// conform: origin=print is a prelude function: no import, any value as text, then a newline
type Point {
	x Int
	y Int
}

fn main() Void {
	print("hello")
	print(42)
	print(Point(1, 2))
	print([1, 2, 3])

	name := "ms"
	print(f"name: {name}")
}
// expect-exit: 0
// expect-stdout: hello
// expect-stdout: 42
// expect-stdout: Point(x: 1, y: 2)
// expect-stdout: [1, 2, 3]
// expect-stdout: name: ms
