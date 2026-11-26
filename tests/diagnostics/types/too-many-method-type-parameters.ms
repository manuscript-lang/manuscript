// conform: tags=functions,generics,tier-core
// conform: phase=check
// A method counts its receiver's type parameters toward the 16 a function declares; the 17th
// is reported at the method, not as an internal error while lowering a call.
type B[T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, T15, T16] {
	a T0
}

fn B[T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, T15, T16].get() Int => 1
// expect-error: MS3000 9:81 a method takes at most 16 type parameters, its receiver's included; group related ones into a record type
