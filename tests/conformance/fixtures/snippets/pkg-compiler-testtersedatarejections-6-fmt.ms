# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/terse_data_test.go:39 TestTerseDataRejections
def f() -> Unit:
    let value = {1: 2}
