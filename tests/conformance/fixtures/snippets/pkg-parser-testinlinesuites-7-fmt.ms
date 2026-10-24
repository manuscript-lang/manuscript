# conform: tags=control-flow,formatter,parser,tier-core,with-cleanup
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:204 TestInlineSuites
def f() -> Unit:
    while True: break
    for x in values: consume(x)
    with resource() as x: consume(x)
