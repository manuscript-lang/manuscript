// conform: tags=diagnostics,formatter,generics,optional,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/generics.md:74
type Pair[A, B = A] {
	first A
	second B
}

fn parse[T = String](text String) T? {
	return null
}

same Pair[Int] := Pair[Int](1, 2)  // Pair[Int, Int]
mixed := Pair[Int, String](1, "x")
// expect-error: MS3070 13:19 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 14:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
