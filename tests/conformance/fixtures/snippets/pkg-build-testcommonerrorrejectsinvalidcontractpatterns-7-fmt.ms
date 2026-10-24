# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:91 TestCommonErrorRejectsInvalidContractPatterns
interface Diagnostic:
    def message() -> String

type LocalError:
    detail: String

impl Diagnostic for LocalError:
    def message() -> String:
        return self.detail

def wrong(value: LocalError) -> Diagnostic:
    return value
