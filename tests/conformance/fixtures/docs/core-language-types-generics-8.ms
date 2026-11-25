// conform: tags=diagnostics,generics,records,sets,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/generics.md:130
// Rejected at declaration: missing Equal bound.
fn unchecked_same[T](left T, right T) Bool {
	return left == right
}

type Keys[T Hashable] {
	values Set[T]
}
// expect-error: MS3000 6:17 equality requires Equal operands; T has no equality, so give it 'fn T.equals(other: T) Bool' or compare fields
