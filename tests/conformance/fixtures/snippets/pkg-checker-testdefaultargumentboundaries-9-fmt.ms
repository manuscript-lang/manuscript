# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:22 TestDefaultArgumentBoundaries
def f(value: Int = 1) -> Int:
    return value

def call() -> Int:
    let copy: Callable[[Int], Int] = f
    return copy()
