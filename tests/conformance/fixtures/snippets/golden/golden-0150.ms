// conform: tags=diagnostics
// conform: phase=check
interface Diagnostic:
    fn message() String
type LocalError:
    detail: String
impl Diagnostic for LocalError:
    fn message() String:
        return self.detail
fn wrong(value: LocalError) Diagnostic:
    return value
