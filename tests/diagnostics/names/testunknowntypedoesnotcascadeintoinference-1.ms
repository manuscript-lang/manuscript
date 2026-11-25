// conform: tags=closures,diagnostics,faults,formatter,generics,lists,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/checker/inference_hints_test.go:45 TestUnknownTypeDoesNotCascadeIntoInference
fn collect[T, U](items List[T], step fn(T) List[U]!MissingError) List[U]!MissingError {
	return step(items[0])
}

fn first() Void {
	result := collect(
		items: [1, 2],
		step: fn(value Int) List[Int]!MissingError => ok([value])
	)
	unrelated Int := "wrong"
}
// expect-error: MS2001 4:52 unknown type MissingError; declare it with 'type MissingError:' / 'enum MissingError:' / 'interface MissingError:', declare it as a type parameter, or import it
// expect-error: MS2001 4:74 unknown type MissingError; declare it with 'type MissingError:' / 'enum MissingError:' / 'interface MissingError:', declare it as a type parameter, or import it
// expect-error: MS2001 11:39 unknown type MissingError; declare it with 'type MissingError:' / 'enum MissingError:' / 'interface MissingError:', declare it as a type parameter, or import it
// expect-error: MS3001 13:22 expected Int, found String (in the initializer of 'unrelated')
