# conform: tags=formatter,interpolation,parser,strings,testing,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/navigation_test.go:86 TestNativeGenericMethodNavigation
def label(value: Int) -> String:
    return f"{value}"

test "methods":
    let _labels = [1].map(transform: label)
    let _convert = [2].map[String]
    let _text = " hello ".trim()
