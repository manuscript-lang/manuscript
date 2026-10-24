# conform: tags=control-flow,diagnostics,generics,lists,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/list_bounds_test.go:64 TestClosedIntListGenericAndLambdaIsolation
def count[T](values: List[T]) -> Int: return values.length()

def probe() -> Int:
    let values = [1, 2, 3]
    var sum = 0
    var i = 0

    while i < 1000:
        sum += count[Int](values)
        i += 1

    return sum
