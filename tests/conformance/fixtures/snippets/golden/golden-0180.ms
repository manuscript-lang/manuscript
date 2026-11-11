// conform: tags=diagnostics
// conform: phase=check
type Data:
    value: Int
fn record[T: Data](value: T) Unit: return
