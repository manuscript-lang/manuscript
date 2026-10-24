# conform: tags=closures,control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/list_bounds_test.go:74 TestClosedIntListGenericAndLambdaIsolation
def probe(value: Int) -> Int:
    let values = [1, 2, 3]

    let callback = lambda () -> Int:
        var sum = value
        for item in values:
            sum += item
        return sum

    return callback()
