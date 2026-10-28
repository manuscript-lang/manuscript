# conform: tags=control-flow,formatter,generics,interfaces,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:150 TestCommonErrorRejectsInvalidContractPatterns
type Box[T]:
    item: T

impl Error for Box[T]:
    fn message() String:
        return "box"

fn wrong(cause: Error) String:
    match cause:
        Box(value):
            return value.message()
        _:
            return cause.message()
