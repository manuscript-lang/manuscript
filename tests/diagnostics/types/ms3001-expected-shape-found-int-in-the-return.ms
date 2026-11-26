// conform: tags=diagnostics
// conform: phase=check
interface Shape {
	fn area() Int
}

fn f() Shape => 1
// expect-error: MS3001 7:17 expected Shape, found Int (in the return value); use a concrete value implementing Shape
