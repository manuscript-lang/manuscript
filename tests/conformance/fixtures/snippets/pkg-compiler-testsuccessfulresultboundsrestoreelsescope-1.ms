# conform: tags=control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/result_bounds_test.go:127 TestSuccessfulResultBoundsRestoreElseScope
fn probe(found: Int) Int:
    var sum = 0
    var i = 0

    while i < 1000:
        if let fresh = affine(i):
            sum += fresh
        else:
            sum += found

        i += 1

    return sum
