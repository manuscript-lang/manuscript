// conform: tags=diagnostics
// conform: phase=check
type Key%d:
    value: Int
impl Tag for Key%d:
    fn tag() Int: self.value
