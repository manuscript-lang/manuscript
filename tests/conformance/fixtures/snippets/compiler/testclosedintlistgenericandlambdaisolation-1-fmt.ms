# conform: tags=control-flow,formatter,generics,lists,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:64 TestClosedIntListGenericAndLambdaIsolation
fn count[T](values: List[T]) Int: return values.length()

fn probe() Int:
    let values = [1, 2, 3]
    var sum = 0
    var i = 0

    while i < 1000:
        sum += count[Int](values)
        i += 1

    return sum
