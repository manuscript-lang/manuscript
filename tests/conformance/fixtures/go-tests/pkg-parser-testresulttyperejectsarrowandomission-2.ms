# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:26 TestResultTypeRejectsArrowAndOmission
fn f(g: fn(value: Int) -> Int) Int: 1
