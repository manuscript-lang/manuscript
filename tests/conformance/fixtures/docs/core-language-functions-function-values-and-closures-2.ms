// conform: tags=closures,diagnostics,records,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/functions/function-values-and-closures.md:27
fn subtract_one(amount Int) Int {
	return amount - 1
}

fn adapt() Void {
	// Rejected: amount and value are different function-type labels.
	invalid fn(Int) Int := subtract_one
	renamed := fn(value Int) Int {
		return subtract_one(amount: value)
	}
	result := apply(value: 3, transform: renamed)
}
// expect-error: MS2001 14:15 unknown binding apply; declare it with 'apply := ...' before use, define 'fn apply(...) T { ... }', or import it from a module
