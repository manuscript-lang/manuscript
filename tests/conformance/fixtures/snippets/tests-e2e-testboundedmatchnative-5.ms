# conform: tags=control-flow,diagnostics,faults,mutation,tier-core
# conform: phase=check
# conform: origin=tests/e2e/match_bounds_test.go:79 TestBoundedMatchNative
export fn main() Int:
    let shapes = [Shape.Circle(2)]
    var sum = 9223372036854775807
    var i = 0

    while i < 2:
        sum += area(shapes.get(0))
        i += 1

    return sum
