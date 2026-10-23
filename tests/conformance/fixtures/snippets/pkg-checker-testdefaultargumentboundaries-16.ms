# conform: tags=closures,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:29 TestDefaultArgumentBoundaries
fn f() Unit:
    var outer = 1
    let callback = fn(
        value: Int = (
            fn() Int:
                outer = 2
                return outer
        )()
    ) Int:
        return value
