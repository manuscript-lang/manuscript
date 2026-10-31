# conform: tags=interpolation,strings,testing,tier-core
# conform: phase=test
# conform: origin=pkg/tooling/lsp/navigation_test.go:86 TestNativeGenericMethodNavigation
fn label(value: Int) String:
    return "{value}"

test "methods":
    let _labels = [1].map(transform: label)
    let _convert = [2].map[String]
    let _text = " hello ".trim()
