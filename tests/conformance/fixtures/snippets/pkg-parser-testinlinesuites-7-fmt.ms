# conform: tags=control-flow,formatter,parser,tier-core,with-cleanup
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:204 TestInlineSuites
fn f() Unit:
    while true: break
    for x in values: consume(x)
    with let x = resource(): consume(x)
