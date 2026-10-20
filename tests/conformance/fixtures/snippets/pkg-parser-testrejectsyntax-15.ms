# conform: tags=interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:48 TestRejectSyntax
fn f() String:
    return "{1 # comment}"
