# conform: tags=control-flow,diagnostics,generics,interfaces,match,records,strings,tier-core
# conform: phase=check
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
