# conform: tags=parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:38 TestSyntaxErrorsStateTheFix
fn f() String:
    return "a\q"
