// conform: tags=diagnostics,mutation
// conform: phase=check
type Counter:
    count: Int

fn Counter.bump() Unit:
    self.count += 1
