# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/constants_test.go:80 TestNavigationSurvivesUnterminatedDelimiterInsideBody
fn add(a: Int, b: Int) Int:
    return a + b

export fn main() Int:
    let label = "héllo 😀"
    let s = add(a: 1, b: 2)
    let q = (
    return s
