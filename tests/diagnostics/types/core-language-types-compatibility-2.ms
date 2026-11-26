// conform: tags=diagnostics,formatter,lists,modules,optional,records,stdlib-errors,strings,tier-stdlib,try-result
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/compatibility.md:43

type Input {
	names List[String?]
}

input := Input([null, "Ada"])
nested List[List[Int]] := [[], [1]]
success Result[Int, Error] := ok(1)
failure Result[Int, Error] := error(Error("unavailable"))
// Rejected: the result error type cannot be inferred from ok's payload.
incomplete := ok(1)
// expect-error: MS3070 9:10 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 11:31 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 12:31 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 14:15 a constant takes literals, operators, collections, and other constants; compute this value in a function
