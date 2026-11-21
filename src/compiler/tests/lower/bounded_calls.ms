interface Shape:
	fn area() Int

type Square:
	side: Int

fn Square.area() Int:
	return self.side * self.side

fn total[T: Shape](a: T, b: T) Int:
	return a.area() + b.area()

fn bigger[T: Comparable](a: T, b: T) Bool:
	return a.compare(b) > 0

fn same[T: Equal](a: T, b: T) Bool:
	return a.equals(b)

fn main() Int:
	x := Square(side: 2)
	y := Square(side: 3)
	if bigger(4, 3) and same("a", "a"): return total(x, y)

	return 0
