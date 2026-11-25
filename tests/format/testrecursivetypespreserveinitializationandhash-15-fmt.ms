// conform: tags=formatter,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/recursive_types_test.go:48 TestRecursiveTypesPreserveInitializationAndHashing
type Pair {
	left Int
	right Int
}

fn hash(pair Pair) Int => return pair.hash()
// expect-format: rewritten
// expect-formatted: type Pair {
// expect-formatted: \tleft, right Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn hash(pair Pair) Int => return pair.hash()
