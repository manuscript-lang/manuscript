# conform: tags=parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_tail_test.go:19 TestTailResultIdentityLowering
let output = try value
    return ok(output + 1)
