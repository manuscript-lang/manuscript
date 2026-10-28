# conform: tags=formatter,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:79 TestCommonErrorRejectsInvalidContractPatterns
fn wrong() Result[String, Error]:
    return Result[Int, JsonError].ok(value: 1)
