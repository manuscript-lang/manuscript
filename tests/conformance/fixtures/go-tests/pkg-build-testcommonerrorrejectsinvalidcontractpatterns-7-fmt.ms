# conform: tags=control-flow,formatter,interfaces,parser,records,strings,tier-core
# conform: phase=parse
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
