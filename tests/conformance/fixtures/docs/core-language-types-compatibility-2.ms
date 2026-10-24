# conform: tags=diagnostics,lists,modules,optional,records,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=check
# conform: origin=documentation/core-language/types/compatibility.md:43
from "@std/core.ms" import TextError

type Input:
    names: List[Optional[String]]

let input = Input([none, some("Ada")])
let nested: List[List[Int]] = [[], [1]]
let success: Result[Int, TextError] = ok(1)
let failure: Result[Int, TextError] = error(TextError("unavailable"))
# Rejected: the result error type cannot be inferred from ok's payload.
let incomplete = ok(1)
