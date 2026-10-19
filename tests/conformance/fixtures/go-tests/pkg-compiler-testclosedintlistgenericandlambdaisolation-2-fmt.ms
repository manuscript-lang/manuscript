# conform: tags=closures,control-flow,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:74 TestClosedIntListGenericAndLambdaIsolation
fn probe(value: Int) Int:
    let values = [1, 2, 3]
    let callback = fn() Int:
        var sum = value
        for item in values:
            sum += item
        return sum
    return callback()
