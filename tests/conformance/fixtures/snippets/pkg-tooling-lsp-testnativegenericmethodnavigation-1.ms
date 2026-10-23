# conform: tags=interpolation,strings,testing,tier-core
# conform: phase=test
# conform: origin=pkg/tooling/lsp/navigation_test.go:86 TestNativeGenericMethodNavigation
fn label(value: Int) String:
    return "{value}"

test "methods":
    let labels = [1].map(transform: label)
    let convert = [2].map[String]
    let text = " hello ".trim()
