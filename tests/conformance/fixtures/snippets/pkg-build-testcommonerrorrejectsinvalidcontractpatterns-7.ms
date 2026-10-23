# conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/build/library_test.go:91 TestCommonErrorRejectsInvalidContractPatterns
interface Diagnostic:
    fn message() String

type LocalError:
    detail: String

impl Diagnostic for LocalError:
    fn message() String:
        return self.detail

fn wrong(value: LocalError) Diagnostic:
    return value
