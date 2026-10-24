# conform: tags=closures,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:29 TestDefaultArgumentBoundaries
def f() -> Unit:
    var outer = 1
    let callback = lambda (
        value: Int = (
            lambda () -> Int:
                outer = 2
                return outer
        )()
    ) -> Int:
        return value
