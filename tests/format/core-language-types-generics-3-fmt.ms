// conform: tags=formatter,generics,parser,records,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/generics.md:49
type Box[T] {
	value T
}

fn identity[T](value T) T {
	return value
}

fn same[T Equal](left T, right T) Bool {
	return left == right
}

box := Box[Int](1)
exact := identity[Int](1)
inferred := identity(1)
// expect-format: rewritten
// expect-formatted: type Box[T] {
// expect-formatted: \tvalue T
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn identity[T](value T) T {
// expect-formatted: \treturn value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn same[T Equal](left, right T) Bool {
// expect-formatted: \treturn left == right
// expect-formatted: }
// expect-formatted:
// expect-formatted: box := Box[Int](1)
// expect-formatted: exact := identity[Int](1)
// expect-formatted: inferred := identity(1)
