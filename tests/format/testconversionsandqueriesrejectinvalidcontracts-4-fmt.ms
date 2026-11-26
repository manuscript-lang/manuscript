// conform: tags=alternatives,formatter,generics,optional,parser,records,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/conversions_queries_test.go:25 TestConversionsAndQueriesRejectInvalidContracts
enum T!E {
    ok(value: T)
    error(cause: E)
}

fn wrong(value: Int!String) Int? => value.to_optional()
// expect-error: MS1000 4:7-4:8 expected '{', found '!'; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
// expect-format-exit: 1
