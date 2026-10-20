# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/terse_data_test.go:18 TestTerseDataRejections
let first = 1
    let value = f(first, first: 2, second: 3)
