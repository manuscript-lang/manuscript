# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:203 TestInlineSuites
def f() -> Unit:
    let g = lambda (x: Int) -> Int: return x
    use(lambda (x: Int) -> Int: return x, other: 1)

    let gs = [lambda () -> Unit: return, lambda () -> Int: return 2]
