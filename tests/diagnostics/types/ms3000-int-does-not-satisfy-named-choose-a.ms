// conform: tags=diagnostics
// conform: phase=check
interface Named {
	fn name() String
}

fn f[T Named = Int]() Void => void
// expect-error: MS3000 7:16 Int does not satisfy Named; choose a default that already implements it
