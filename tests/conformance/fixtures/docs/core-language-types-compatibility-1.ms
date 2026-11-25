// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/compatibility.md:26
fn identity(value Int) Int {
	return value
}

exact fn(Int) Int := identity
// Rejected: amount differs from value.
relabeled fn(Int) Int := identity
// expect-error: MS3000 8:22 a constant can refer only to other constants, but identity is a function; compute the value in a function
// expect-error: MS3000 10:26 a constant can refer only to other constants, but identity is a function; compute the value in a function
