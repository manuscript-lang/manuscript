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
	return count(Opt.None)
}
