# conform: tags=control-flow,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:89 TestClosedIntListGenericAndLambdaIsolation
fn probe() Int:
    let values = [1, 2, 3]
    var sum = 0
    for item in values:
        sum += item
    return sum + values.length()
