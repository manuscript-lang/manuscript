# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_tail_test.go:39 TestTailResultIdentityPreservesDebugBindings
import TextError from "@std/core.ms"

fn tail(value: Int!TextError) Int!TextError:
    let output = try value
    return ok(output)
