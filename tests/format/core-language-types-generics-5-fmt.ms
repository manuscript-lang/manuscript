// conform: tags=control-flow,formatter,generics,parser,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/generics.md:92
fn choose[T](first T, second T) T {
	return first
}

value := choose(1, 2)  // T = Int
// Rejected: conflicting evidence for T.
mixed := choose(1, 2.0)
// expect-format: rewritten
// expect-formatted: fn choose[T](first, second T) T {
// expect-formatted: \treturn first
// expect-formatted: }
// expect-formatted:
// expect-formatted: value := choose(1, 2)  // T = Int
// expect-formatted: // Rejected: conflicting evidence for T.
// expect-formatted: mixed := choose(1, 2.0)
