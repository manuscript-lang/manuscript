# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:30 TestDefaultArgumentBoundaries
fn grow[T](value: T, optional: Int = grow(value: [value])) Int:
    return optional
