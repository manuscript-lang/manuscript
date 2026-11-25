// conform: tags=diagnostics,alternatives,tier-core
// conform: phase=check
// conform: origin=issue 6804
enum Shape {
	Circle(radius Int)
	Square(side Int)
}

fn describe(shape Shape) String {
	return f"{shape}"
}

export fn main() Void {
	print(describe(Shape.Circel(1)))
}
// expect-error: MS2001 14:26 unknown alternative case Circel of Shape; cases: Circle, Square
