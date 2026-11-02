# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/lambda_keyword_test.go:51 TestUnitBindingKeywordDiagnostic
fn f() Unit:
    let code_unit = unit
    return code_unit
