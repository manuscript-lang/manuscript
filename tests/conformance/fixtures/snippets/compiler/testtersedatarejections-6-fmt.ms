# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/terse_data_test.go:39 TestTerseDataRejections
fn f() Unit:
    let _value = {1: 2}
