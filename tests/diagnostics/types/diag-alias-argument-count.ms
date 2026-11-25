// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=type-aliases
type Bad[T] = List[T]

fn f(x Bad) Int {
	return 0
}
// expect-error: MS3000 6:8 alias Bad takes 1 type arguments, found 0; write Bad[T1]
