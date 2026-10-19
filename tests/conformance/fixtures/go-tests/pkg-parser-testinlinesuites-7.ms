# conform: tags=control-flow,diagnostics,tier-core,with-cleanup
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:204 TestInlineSuites
fn f() Unit:
    while true: break
    for x in values: consume(x)
    with x = resource(): consume(x)
