# conform: tags=control-flow,diagnostics,generics,interfaces,match,records,strings,tier-core
# conform: phase=check
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
