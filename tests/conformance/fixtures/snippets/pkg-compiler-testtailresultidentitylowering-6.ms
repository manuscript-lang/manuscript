# conform: tags=parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_tail_test.go:20 TestTailResultIdentityLowering
let output = try value
    return ok(output.to_string())
