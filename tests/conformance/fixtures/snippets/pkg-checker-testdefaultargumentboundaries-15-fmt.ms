# conform: tags=closures,formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:28 TestDefaultArgumentBoundaries
fn run[T](operation: fn() T) T:
    return operation()
fn f(value: Int = 1) Int:
    return value
fn call() Int:
    return run(f)
