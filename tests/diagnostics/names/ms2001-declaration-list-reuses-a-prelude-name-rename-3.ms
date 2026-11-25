// conform: tags=diagnostics
// conform: phase=check
export type List[T] {
	value T
}
// expect-error: MS2001 3:8 declaration List reuses a prelude name; rename it, because List always refers to the standard declaration
