// conform: tags=diagnostics
// conform: phase=check
type Trio[A, B, C = A] {
	first A
}

fn use(t Trio[Int]) Void => void
// expect-error: MS3000 7:10 Trio takes 2 to 3 type arguments, found 1; write Trio[T1, T2, T3]
