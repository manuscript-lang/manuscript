// conform: tags=alternatives,faults,formatter,generics,parser,records,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/core_parity_test.go:24 TestCoreParityRejectsInvalidContracts
enum T!E {
    ok(value: T)
    error(cause: E)
}

fn wrong(value: Int!String) Int => value.get()
// expect-error: MS1000 4:7-4:8 expected '{', found '!'; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
// expect-format-exit: 1
