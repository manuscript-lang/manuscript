# conform: tags=closures,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/int_bounds_test.go:60 TestScalarIntBoundsIsolateBranchesAndClosures
def probe(value: Int) -> Int:
    var sum = 0
    sum = value

    let callback = lambda () -> Int:
        return sum + value
    return callback()
