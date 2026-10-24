# conform: tags=control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/result_bounds_test.go:148 TestSuccessfulResultSubtractBounds
def probe() -> Int:
    var sum = 0
    var i = 0

    while i < 1000:
        if let found = wrapped(i):
            sum += found
        i += 1

    return sum
