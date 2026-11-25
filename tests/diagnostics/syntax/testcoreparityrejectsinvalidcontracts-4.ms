// conform: tags=alternatives,diagnostics,faults,generics,records,strings,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/core_parity_test.go:24 TestCoreParityRejectsInvalidContracts
enum T!E {
    ok(value: T)
    error(cause: E)
}

fn wrong(value: Int!String) Int => value.get()
// expect-error: MS1000 4:7-4:8 expected '{', found '!'; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
// expect-error: MS1000 9:15-9:16 remove the ':' between 'value' and its type; write value Type
// expect-fix: 9:15-9:16 ""
