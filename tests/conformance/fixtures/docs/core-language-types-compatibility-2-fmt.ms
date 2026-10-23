# conform: tags=formatter,lists,modules,optional,parser,records,stdlib-errors,strings,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/types/compatibility.md:43
import {TextError} from "@std/core.ms"

type Input:
    names: List[Optional[String]]

let input = Input([none, some("Ada")])
let nested: List[List[Int]] = [[], [1]]
let success: Result[Int, TextError] = ok(1)
let failure: Result[Int, TextError] = error(TextError("unavailable"))
# Rejected: the result error type cannot be inferred from ok's payload.
let incomplete = ok(1)
