# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/lambda_keyword_test.go:40 TestUnitBindingKeywordDiagnostic
def before() -> Unit: ()

def broken() -> Unit: ...
