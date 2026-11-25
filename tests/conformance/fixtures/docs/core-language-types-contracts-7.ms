// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/contracts.md:127
fn use_increment(operation Increment) Int {
	return operation.apply(1)
}

offset := Offset(2)
view := Increment(offset)
result := use_increment(view)
// Rejected: conversion is not implicit at a call boundary.
wrong := use_increment(offset)
// expect-error: MS2001 4:28 unknown type Increment; declare it with 'type Increment:' / 'enum Increment:' / 'interface Increment:', declare it as a type parameter, or import it
// expect-error: MS3070 8:11 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 9:9 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 10:11 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 12:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
