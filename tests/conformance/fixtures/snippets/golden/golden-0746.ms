// conform: tags=diagnostics
// conform: phase=check
type Cause:
    text: String
impl Error for Cause:
    fn message() String: self.text
