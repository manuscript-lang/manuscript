// conform: tags=functions,generics,tier-core
// conform: phase=check
// A function declares at most 16 type parameters; the 17th is reported where it is written,
// not as an internal error while lowering a call.
fn f[T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, T15, T16](a0 T0, a1 T1) Int {
	return 1
}
// expect-error: MS3000 5:76 a function takes at most 16 type parameters; group related ones into a record type
