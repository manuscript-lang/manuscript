# conform: tags=closures,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:29 TestDefaultArgumentBoundaries
def f() -> Unit:
    var outer = 1
    let _callback = lambda (
        value: Int = (
            lambda () -> Int:
                outer = 2
                return outer
        )()
    ) -> Int:
        return value
