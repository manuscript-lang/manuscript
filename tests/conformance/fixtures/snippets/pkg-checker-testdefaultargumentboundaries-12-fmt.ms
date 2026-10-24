# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:25 TestDefaultArgumentBoundaries
def f(value: Int = 1) -> Int:
    return value

def make() -> Callable[[Int], Int]:
    return f

def call() -> Int:
    return make()()
