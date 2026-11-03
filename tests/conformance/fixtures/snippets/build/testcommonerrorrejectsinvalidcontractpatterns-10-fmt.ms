# conform: tags=formatter,match,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:111 TestCommonErrorRejectsInvalidContractPatterns
interface Named:
    fn name() String

fn wrong(item: Named) String:
    match item:
        Circle.Big(value):
            return "invalid"
        _:
            return item.name()
