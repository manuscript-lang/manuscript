// conform: tags=diagnostics
// conform: phase=check
type E:
    text: String
impl Error for E:
    fn message() String: self.text
fn error_value() Error: E("bad input")
