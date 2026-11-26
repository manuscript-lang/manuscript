// conform: tags=ownership,closures,generics
// conform: phase=run
// A closure's own parameter sits at the same position as a parameter of the function around
// it. Handing the closure's parameter on says nothing about the function's.
type Cursor {
	at Int
}

type Drawn[T] {
	value T
	cursor Cursor
}

type Gen[T] {
	make fn(move Cursor) Drawn[T]
}

fn constant[T Clonable](value T) Gen[T] {
	own := value.clone()
	return Gen[T](c => Drawn(own.clone(), c))
}

fn main() Void {
	drawn := constant(5).make(Cursor(1))
	print(drawn.value + drawn.cursor.at)
}
// expect-exit: 0
// expect-stdout: 6
