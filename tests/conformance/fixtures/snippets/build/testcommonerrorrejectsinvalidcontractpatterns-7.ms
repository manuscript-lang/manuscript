// conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
// conform: phase=check
// conform: origin=pkg/build/library_test.go:91 TestCommonErrorRejectsInvalidContractPatterns
interface Diagnostic:
    fn message() String

type LocalError:
    detail: String

fn LocalError.message() String:
    return self.detail.clone()

fn wrong(value: LocalError) Diagnostic:
    return value
