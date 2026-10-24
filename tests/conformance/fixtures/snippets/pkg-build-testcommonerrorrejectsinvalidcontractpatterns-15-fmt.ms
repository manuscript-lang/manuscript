# conform: tags=control-flow,formatter,generics,interfaces,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:150 TestCommonErrorRejectsInvalidContractPatterns
type Box[T]:
    item: T

impl Error for Box[T]:
    def message() -> String:
        return "box"

def wrong(cause: Error) -> String:
    match cause:
        case Box(value):
            return value.message()
        case _:
            return cause.message()
