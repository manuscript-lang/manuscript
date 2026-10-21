# conform: tags=formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_tail_test.go:63 TestTailResultIdentityKeepsErrorWidening
import TextError from "@std/core.ms"
fn tail(value: Result[Int, TextError]) Result[Int, Error]:
    let output = try value
    return ok(output)
