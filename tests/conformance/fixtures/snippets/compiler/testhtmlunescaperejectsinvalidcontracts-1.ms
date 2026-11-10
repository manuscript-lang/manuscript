// conform: tags=diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/html_unescape_test.go:12 TestHTMLUnescapeRejectsInvalidContracts
fn wrong() String:
    convert := unescape
    return convert(value: "&amp;")
