# conform: tags=closures,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/int_bounds_test.go:60 TestScalarIntBoundsIsolateBranchesAndClosures
fn probe(value: Int) Int:
    var sum = 0
    let callback = fn() Int:
        return sum + value
    sum = value
    return callback()
