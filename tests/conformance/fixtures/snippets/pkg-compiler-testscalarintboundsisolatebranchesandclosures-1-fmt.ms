# conform: tags=control-flow,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/int_bounds_test.go:52 TestScalarIntBoundsIsolateBranchesAndClosures
def probe(value: Int, flag: Bool) -> Int:
    var sum = value

    if flag:
        sum = 0
    else:
        sum += 1

    return sum
