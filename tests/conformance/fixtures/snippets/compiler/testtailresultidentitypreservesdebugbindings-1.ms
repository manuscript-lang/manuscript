# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_tail_test.go:39 TestTailResultIdentityPreservesDebugBindings

fn tail(value: Int!Error) Int!Error:
    let output = try value
    return ok(output)
