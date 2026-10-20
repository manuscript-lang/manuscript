# conform: tags=control-flow,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:91 TestSuccessfulResultBoundsRejectDifferentReturns
fn probe() Int:
    var sum = 0
    var i = -1
    while i < 1000:
        if let found = affine(i):
            sum += found
        i += 1
    return sum
