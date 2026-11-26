// conform: tags=diagnostics
// conform: phase=check
export type Map[K, V] {
	value V
}

export type MapEntry[K, V] {
	value V
}

export type CollectionError {
	message String
}
// expect-error: MS2001 3:8 declaration Map reuses a prelude name; rename it, because Map always refers to the standard declaration
// expect-error: MS2001 7:8 declaration MapEntry reuses a prelude name; rename it, because MapEntry always refers to the standard declaration
