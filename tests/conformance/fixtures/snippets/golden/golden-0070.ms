// conform: tags=diagnostics
// conform: phase=check
impl Increment for Offset:
    fn apply(value: Int) Int:
        return value + self.delta
