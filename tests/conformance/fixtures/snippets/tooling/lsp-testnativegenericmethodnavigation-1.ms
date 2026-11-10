// conform: tags=interpolation,strings,testing,tier-core
// conform: phase=test
// conform: origin=pkg/tooling/lsp/navigation_test.go:86 TestNativeGenericMethodNavigation
fn label(value: Int) String:
    return "{value}"

test "methods":
    _labels := [1].map(transform: label)
    _convert := [2].map[String]
    _text := " hello ".trim()
