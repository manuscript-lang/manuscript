# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:203 TestInlineSuites
fn f() Unit:
    let g = fn(x: Int) Int: return x
    use(fn(x: Int) Int: return x, other: 1)

    let gs = [fn() Unit: return, fn() Int: return 2]
