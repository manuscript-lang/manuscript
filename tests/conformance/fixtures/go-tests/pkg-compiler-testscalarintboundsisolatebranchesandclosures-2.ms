# conform: tags=closures,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/int_bounds_test.go:60 TestScalarIntBoundsIsolateBranchesAndClosures
fn probe(value: Int) Int:
    var sum = 0
    let callback = fn() Int:
        return sum + value
    sum = value
    return callback()
