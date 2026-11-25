// conform: tags=diagnostics
// conform: phase=check
type ListEntry[T] {
	payload T
}

fn get() List[ListEntry[Int]] => [1].entries()
// expect-error: MS2001 3:1 declaration ListEntry reuses a prelude name; rename it, because ListEntry always refers to the standard declaration
