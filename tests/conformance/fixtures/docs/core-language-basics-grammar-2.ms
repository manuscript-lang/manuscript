// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/basics/grammar.md:64
fn example() Int {
	return apply(value: 3, transform: (fn(value Int) Int => return value - 1))
}
// expect-error: MS2001 5:12 unknown binding apply; declare it with 'apply := ...' before use, define 'fn apply(...) T { ... }', or import it from a module
