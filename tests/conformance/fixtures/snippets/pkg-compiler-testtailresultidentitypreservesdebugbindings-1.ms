# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_tail_test.go:39 TestTailResultIdentityPreservesDebugBindings
from "@std/core.ms" import TextError

def tail(value: Result[Int, TextError]) -> Result[Int, TextError]:
    let output = try value
    return ok(output)
