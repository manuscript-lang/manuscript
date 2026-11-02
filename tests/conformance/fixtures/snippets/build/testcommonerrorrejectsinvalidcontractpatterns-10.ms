# conform: tags=diagnostics,match,strings,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:111 TestCommonErrorRejectsInvalidContractPatterns
interface Named:
    fn name() String

fn wrong(item: Named) String:
    match item:
        Circle.Big(value):
            return "invalid"
        _:
            return item.name()
