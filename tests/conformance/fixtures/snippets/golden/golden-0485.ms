// conform: tags=diagnostics
// conform: phase=check
interface Read:
    fn get() Int
type Box:
    value: Int
impl Read for Box:
    fn get() Int: self.value
fn first() Read: identity(Box(1))