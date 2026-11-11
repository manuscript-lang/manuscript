// conform: tags=diagnostics
// conform: phase=check
fn bump(by: Int = 1) Int:
        self.total += by
        return self.total