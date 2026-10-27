# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/terse_data_test.go:39 TestTerseDataRejections
def f() -> Unit:
    let _value = {1: 2}
