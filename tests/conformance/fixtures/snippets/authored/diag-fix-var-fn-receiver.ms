// conform: tags=diagnostics,mutation
// conform: phase=check
type Counter:
    count Int

fn Counter.bump() Void:
    self.count += 1
