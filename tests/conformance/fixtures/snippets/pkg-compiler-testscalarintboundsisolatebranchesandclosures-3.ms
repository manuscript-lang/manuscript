# conform: tags=control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/int_bounds_test.go:67 TestScalarIntBoundsIsolateBranchesAndClosures
def probe(value: Int, flag: Bool) -> Int:
    var sum = 0
    if flag:
        sum = value
    sum += 1
    return sum
