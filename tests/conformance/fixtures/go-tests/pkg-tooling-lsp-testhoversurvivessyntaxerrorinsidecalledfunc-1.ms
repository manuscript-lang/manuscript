# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/constants_test.go:66 TestHoverSurvivesSyntaxErrorInsideCalledFunction
fn work(a: Int) Int:
    let b = a + 1
    let c = = 3
    return b

export fn main() Int:
    return work(2)
