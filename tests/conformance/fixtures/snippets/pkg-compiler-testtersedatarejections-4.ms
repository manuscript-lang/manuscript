# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/terse_data_test.go:22 TestTerseDataRejections
let first = 1
    let value = f(first + 1, first: 2)
