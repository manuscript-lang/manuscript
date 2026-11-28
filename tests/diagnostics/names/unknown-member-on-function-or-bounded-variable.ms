// conform: tags=diagnostics,types,generics,functions,tier-core
// conform: phase=check,parse
fn size[T Equal](value T) Int {
	return value.length()
}

type Meters {
	value Int
}

type Feet {
	amount Int
}

type Length = Meters | Feet

fn Length.size() Int {
	return self.value
}

fn one() Int {
	return 1
}

fn main() Void {
	f := one
	print(f.length())
	print(f.name)
	print(size(1))
}
// expect-error: MS2001 4:18 unknown or ambiguous member length on T; no bound of T declares it: add an interface that does to its bounds, or call it on a concrete type
// expect-error: MS2001 18:17 unknown or ambiguous member value on Self; available: size
// expect-error: MS2001 27:13 unknown or ambiguous member length on fn() Int; this type has no fields or operations
// expect-error: MS2001 28:13 unknown or ambiguous member name on fn() Int; this type has no fields or operations
