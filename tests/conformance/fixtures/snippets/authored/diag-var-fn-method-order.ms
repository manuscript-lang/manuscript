// conform: tags=diagnostics,tier-core
// conform: phase=check
type Counter:
    n Int

var fn Counter.inc() Void:
    self.n += 1

export fn main() Int:
    return 0
