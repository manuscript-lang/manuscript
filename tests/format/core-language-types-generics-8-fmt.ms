// conform: tags=formatter,generics,parser,records,sets,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/generics.md:130
// Rejected at declaration: missing Equal bound.
fn unchecked_same[T](left T, right T) Bool {
	return left == right
}

type Keys[T Hashable] {
	values Set[T]
}
// expect-format: rewritten
// expect-formatted: // Rejected at declaration: missing Equal bound.
// expect-formatted: fn unchecked_same[T](left, right T) Bool {
// expect-formatted: \treturn left == right
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Keys[T Hashable] {
// expect-formatted: \tvalues Set[T]
// expect-formatted: }
