// conform: tags=formatter,lists,modules,optional,parser,records,stdlib-errors,strings,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=documentation/core-language/types/compatibility.md:43

type Input:
    names: List[String?]

input := Input([none, "Ada"])
nested: List[List[Int]] = [[], [1]]
success: Result[Int, Error] = ok(1)
failure: Result[Int, Error] = error(Error("unavailable"))
// Rejected: the result error type cannot be inferred from ok's payload.
incomplete := ok(1)
