# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/result_type_test.go:27 TestResultTypeRejectsArrowAndOmission
fn f() Int:
    let g = fn(x) -> Int: x
    return 0
