# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/terse_data_test.go:20 TestTerseDataRejections
let wrong = true
    let value = f(wrong, second: 2)
