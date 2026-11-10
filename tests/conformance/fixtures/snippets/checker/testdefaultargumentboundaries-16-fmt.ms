// conform: tags=closures,formatter,mutation,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/defaults_test.go:29 TestDefaultArgumentBoundaries
fn f() Unit:
    var outer = 1
    _callback := fn(
        value: Int = (
            fn() Int:
                outer = 2
                return outer
        )()
    ) Int:
        return value
