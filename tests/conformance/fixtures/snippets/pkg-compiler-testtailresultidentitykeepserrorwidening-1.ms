# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_tail_test.go:63 TestTailResultIdentityKeepsErrorWidening
from "@std/core.ms" import TextError

def tail(value: Result[Int, TextError]) -> Result[Int, Error]:
    let output = try value
    return ok(output)
