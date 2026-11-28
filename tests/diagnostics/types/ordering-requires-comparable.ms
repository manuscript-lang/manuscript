// conform: tags=diagnostics,types,generics,tier-core
// conform: phase=check,parse
type Point {
	x Int
}

enum Color {
	Red
	Blue
}

fn later[T](left, right T) Bool {
	return left > right
}

fn main() Void {
	print([1] < [2])
	print(Point(1) <= Point(2))
	print(Color.Red >= Color.Blue)
	print(true < false)

	a Int? := 1
	print(a < a)
	print(later(1, 2))
}
// expect-error: MS3000 13:17 ordering requires Comparable operands; T has no order; bound it where it is declared, as in `[T Comparable]`
// expect-error: MS3000 17:15 ordering requires Comparable operands; List[Int] has no order; compare values that have one, such as numbers or text
// expect-error: MS3000 18:20 ordering requires Comparable operands; Point has no order; compare a field that has one, or give it 'fn Point.compare(other Point) Int'
// expect-error: MS3000 19:21 ordering requires Comparable operands; Color has no order; compare a field that has one, or give it 'fn Color.compare(other Color) Int'
// expect-error: MS3000 20:16 ordering requires Comparable operands; Bool has no order; compare values that have one, such as numbers or text
// expect-error: MS3000 23:13 ordering requires Comparable operands; Int? has no order; compare values that have one, such as numbers or text
