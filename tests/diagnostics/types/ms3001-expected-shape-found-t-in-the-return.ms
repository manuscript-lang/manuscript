// conform: tags=diagnostics
// conform: phase=check
interface Shape {
	fn area() Int
}

fn f[T](value T) Shape => value
// expect-error: MS3001 7:27 expected Shape, found T (in the return value); use a concrete value implementing Shape
