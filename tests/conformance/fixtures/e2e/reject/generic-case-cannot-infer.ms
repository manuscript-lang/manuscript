// conform: tags=generics,diagnostics,tier-core
// conform: phase=check
// A payload-less case of a generic enum with nothing that fixes its type arguments is reported where it is written.
enum Opt[T] {
	Has(v T)
	None
}

fn count[T](o Opt[T]) Int {
	return 1
}

export fn main() Int {
	x := Opt.None
	both := [Opt.None, Opt.None]
	arms := match 1 {
		0 => Opt.None
		_ => Opt.None
	}
	return count(Opt.None)
}
// expect-error: MS3080 14:14 cannot infer the type arguments of Opt for this case; annotate the binding or write them, e.g. Opt[Int].None
// expect-error: MS3080 15:18 cannot infer the type arguments of Opt for this case; annotate the binding or write them, e.g. Opt[Int].None
// expect-error: MS3080 15:28 cannot infer the type arguments of Opt for this case; annotate the binding or write them, e.g. Opt[Int].None
// expect-error: MS3080 17:18 cannot infer the type arguments of Opt for this case; annotate the binding or write them, e.g. Opt[Int].None
// expect-error: MS3080 18:18 cannot infer the type arguments of Opt for this case; annotate the binding or write them, e.g. Opt[Int].None
// expect-error: MS3080 20:22 cannot infer the type arguments of Opt for this case; annotate the binding or write them, e.g. Opt[Int].None
