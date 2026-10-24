# conform: tags=closures,diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:37 TestOptionalArgumentBoundaries
def f(value: Int) -> Int: return value

def call() -> Unit:
    let callback: Callable[[Optional[Int]], Int] = f
