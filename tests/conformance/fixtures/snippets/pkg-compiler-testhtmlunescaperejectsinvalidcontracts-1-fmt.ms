# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/html_unescape_test.go:12 TestHTMLUnescapeRejectsInvalidContracts
def wrong() -> String:
    let convert = unescape
    return convert(value: "&amp;")
