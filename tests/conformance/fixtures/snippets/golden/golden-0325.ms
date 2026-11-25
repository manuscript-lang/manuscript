// conform: tags=diagnostics
// conform: phase=check
interface Shape {
	fn area() Int
}

fn f(value fn() Int) Shape => value
// expect-error: MS3001 7:31 expected Shape, found fn() Int (in the return value); use a concrete value implementing Shape
