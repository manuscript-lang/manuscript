// conform: tags=diagnostics,records,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/named-types.md:38
type Options {
	count Int = 3
	total Int = count + 1
}

options := Options(count: 5)  // total defaults to 6
// expect-error: MS3070 9:12 a constant takes literals, operators, collections, and other constants; compute this value in a function
