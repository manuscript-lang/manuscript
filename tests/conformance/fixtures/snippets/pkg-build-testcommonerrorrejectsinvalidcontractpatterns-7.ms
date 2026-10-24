# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
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
