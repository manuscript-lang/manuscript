# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_tail_test.go:63 TestTailResultIdentityKeepsErrorWidening
import TextError from "@std/core.ms"

fn tail(value: Int!TextError) Int!:
    let output = try value
    return ok(output)
