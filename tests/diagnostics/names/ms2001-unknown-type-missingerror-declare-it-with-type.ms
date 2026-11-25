// conform: tags=diagnostics
// conform: phase=check
fn collect[T, U](
	items List[T],
	step fn(T) Result[List[U], MissingError]
) Result[List[U], MissingError] {
	return step(items[0])
}

fn first() Void {
	result := collect(
		items: [1, 2],
		step: fn(value Int) Result[List[Int], MissingError] => ok([value])
	)
	unrelated Int := "wrong"
}
// expect-error: MS2001 5:32 unknown type MissingError; declare it with 'type MissingError:' / 'enum MissingError:' / 'interface MissingError:', declare it as a type parameter, or import it
// expect-error: MS2001 6:19 unknown type MissingError; declare it with 'type MissingError:' / 'enum MissingError:' / 'interface MissingError:', declare it as a type parameter, or import it
// expect-error: MS2001 13:47 unknown type MissingError; declare it with 'type MissingError:' / 'enum MissingError:' / 'interface MissingError:', declare it as a type parameter, or import it
// expect-error: MS3001 15:22 expected Int, found String (in the initializer of 'unrelated')
