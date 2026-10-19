# conform: tags=parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_tail_test.go:17 TestTailResultIdentityLowering
let output = try value
    let unrelated = 1
    return ok(output)
