// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=type-sets
type Number = Int | Float

fn f(x Number) Int {
	return 0
}
// expect-error: MS3000 6:8 Number is a type set, which constrains a type parameter and has no values; write fn f[T Number](...) or use one of its members
