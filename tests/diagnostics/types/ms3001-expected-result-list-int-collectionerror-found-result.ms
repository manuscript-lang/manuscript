// conform: tags=diagnostics
// conform: phase=check
enum CollectionError {
	OutOfRange
}

fn get() Result[List[Int], CollectionError] => [1].slice(0, 1)
// expect-error: MS3001 7:52 expected Result[List[Int], CollectionError], found List[Int]! (in the return value)
