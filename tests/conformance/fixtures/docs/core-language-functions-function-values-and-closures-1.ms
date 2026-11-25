// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/functions/function-values-and-closures.md:10
fn apply(value Int, transform fn(Int) Int) Int {
	return transform(value: value)
}

offset := 1
decrement := fn(value Int) Int {
	return value - offset
}
result := apply(value: 3, transform: decrement)
// expect-error: MS3070 9:14 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 12:11 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3004 5:22 unknown argument value; function values take positional arguments (Int), so pass them without labels
// expect-error: MS3003 5:12 missing argument 1: Int in call to transform; pass it positionally, without a label
