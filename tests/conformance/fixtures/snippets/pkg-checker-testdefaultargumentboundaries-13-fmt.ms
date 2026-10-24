# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:26 TestDefaultArgumentBoundaries
def f(value: Int = 1) -> Int:
    return value

def forward[T](value: T) -> T:
    return value

def call() -> Int:
    let copy = forward(f)
    return copy()
