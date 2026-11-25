// conform: tags=diagnostics
// conform: phase=check
export type List[T] {
	value T
}

export type Set[T] {
	value T
}

export type ListEntry[T] {
	value T
}
// expect-error: MS2001 3:8 declaration List reuses a prelude name; rename it, because List always refers to the standard declaration
// expect-error: MS2001 7:8 declaration Set reuses a prelude name; rename it, because Set always refers to the standard declaration
// expect-error: MS2001 11:8 declaration ListEntry reuses a prelude name; rename it, because ListEntry always refers to the standard declaration
