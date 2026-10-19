# conform: tags=mutation,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_tail_test.go:16 TestTailResultIdentityLowering
var output = try value
    return ok(output)
