// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/basics/grammar.md:88
fn example() Int {
	return apply(transform: fn(value Int) Int => return value - 1, value: 3)
}
// expect-error: MS2001 5:12 unknown binding apply; declare it with 'apply := ...' before use, define 'fn apply(...) T { ... }', or import it from a module
