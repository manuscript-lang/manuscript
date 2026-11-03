# conform: tags=control-flow,formatter,generics,interfaces,match,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:150 TestCommonErrorRejectsInvalidContractPatterns
type Box[T]:
    item: T

interface Named:
    fn name() String

impl Named for Box[T]:
    fn name() String:
        return "box"

fn wrong(item: Named) String:
    match item:
        Box(value):
            return value.name()
        _:
            return item.name()
