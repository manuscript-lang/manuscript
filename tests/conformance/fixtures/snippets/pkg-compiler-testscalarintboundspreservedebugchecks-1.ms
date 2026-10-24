# conform: tags=control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/int_bounds_test.go:83 TestScalarIntBoundsPreserveDebugChecks
def probe() -> Int:
    var sum = 0
    var i = 0

    while i < 100:
        sum += i
        i += 1

    return sum
