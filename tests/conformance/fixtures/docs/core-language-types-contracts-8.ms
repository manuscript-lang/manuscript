// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/contracts.md:146
fn invoke[T Increment](operation T) Int {
	return Increment(operation).apply(1)
}

from_concrete := invoke(offset)
from_view := invoke(view)
// expect-error: MS2001 4:13 unknown type Increment; declare it with 'type Increment:' / 'enum Increment:' / 'interface Increment:', declare it as a type parameter, or import it
// expect-error: MS3070 8:18 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 9:14 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS2001 5:12 unknown binding Increment; declare it with 'Increment := ...' before use, define 'fn Increment(...) T { ... }', or import it from a module
