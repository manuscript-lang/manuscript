# conform: tags=diagnostics,lists,modules,optional,records,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/types/compatibility.md:43

type Input:
    names: List[String?]

let input = Input([none, "Ada"])
let nested: List[List[Int]] = [[], [1]]
let success: Result[Int, Error] = ok(1)
let failure: Result[Int, Error] = error(Error("unavailable"))
# Rejected: the result error type cannot be inferred from ok's payload.
let incomplete = ok(1)
