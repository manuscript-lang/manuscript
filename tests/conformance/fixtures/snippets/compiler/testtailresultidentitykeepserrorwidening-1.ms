# conform: tags=diagnostics,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_tail_test.go:63 TestTailResultIdentityKeepsErrorWidening

fn tail(value: Int!Error) Int!:
    let output = try value
    return ok(output)
